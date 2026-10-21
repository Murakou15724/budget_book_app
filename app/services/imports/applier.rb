module Imports
  class Applier
    Result = Struct.new(:status, :entry, :reason, :reason_codes, :target_id, keyword_init: true)
    ACTIONS = %w[auto_apply approve distinct link adopt_revision hold reject acknowledge_current acknowledge_deleted].freeze
    REVIEWED_ACTIONS = %w[distinct link adopt_revision acknowledge_current acknowledge_deleted].freeze
    TRANSIENT_ERRORS = [ActiveRecord::RecordNotUnique, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout].freeze

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(entry_id:, action:, attributes: {}, target_id: nil, review_token: nil, confirmation: {})
      @entry_id, @action, @target_id, @token = entry_id, action.to_s, target_id, review_token
      @confirmation = confirmation
      @automatic_arguments_invalid = @action == "auto_apply" && (attributes.present? || target_id.present? || review_token.present?)
      @attributes = attributes.to_h.stringify_keys.slice(*ImageImportDraft::EDITABLE_ATTRIBUTES)
    end

    def call
      attempts = 0
      begin
        ImportGuard.synchronize { process }
      rescue *TRANSIENT_ERRORS
        attempts += 1
        retry if attempts <= 2
        Result.new(status: :failed, reason: "database_busy")
      rescue ActiveRecord::RecordInvalid, ArgumentError
        preserve_invalid_edit
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed
        recover_result
      end
    end

    private

    def process
      return Result.new(status: :failed, reason: "invalid_action") unless ACTIONS.include?(@action) && !@automatic_arguments_invalid

      # Guardが先行するため、全て最新のlocking readで取得できる。
      document_id = ImportEntry.where(id: @entry_id).pick(:import_document_id)
      return Result.new(status: :failed, reason: "not_found") unless document_id

      ImportDocument.lock.find(document_id)
      @entry = ImportEntry.lock.find(@entry_id)
      if @entry.reference_entry_id
        representative = ImportEntry.lock.find(@entry.reference_entry_id)
        TargetIntegrity.check!(representative)
        return Result.new(status: representative.terminal? ? :already_processed : :held,
          entry: @entry, reason: "reference_entry")
      end
      TargetIntegrity.check!(@entry)
      return result(:already_processed) if @entry.terminal?
      return result(:conflict) if @entry.state == "conflict" && !%w[acknowledge_current acknowledge_deleted].include?(@action)

      identity = @entry.import_identity_id && ImportIdentity.lock.find(@entry.import_identity_id)
      bound = identity&.bound_entry_id && ImportEntry.lock.find(identity.bound_entry_id)
      TargetIntegrity.check!(bound) if bound
      if bound && bound.id != @entry.id && (bound.state == "conflict" || bound.state == "deletion_acknowledged")
        return result(bound.state == "conflict" ? :conflict : :held, "bound_#{bound.state}")
      end

      draft = ImageImportDraft.lock.find_by!(import_entry_id: @entry.id)
      if @action == "approve"
        CandidateConfirmation.apply(draft, attributes: @attributes, confirmation: @confirmation)
      else
        draft.assign_attributes(@attributes)
      end
      @entry.reload
      if REVIEWED_ACTIONS.include?(@action) && (draft.changed? || !ReviewToken.valid?(@token, entry: @entry, action: @action, target_id: @target_id))
        return result(:held, "review_expired")
      end
      if @action == "link"
        failure = planned_target_failure(draft)
        return failure if failure
      end
      before = Fingerprint.draft_snapshot(ImageImportDraft.find(draft.id))
      draft.save!
      if @action == "approve"
        @entry.event!("edited", details: { "before" => before, "after" => Fingerprint.draft_snapshot(draft), "confirmation" => draft.confirmation_metadata })
      end

      case @action
      when "reject"
        @entry.update!(state: "rejected", reason_code: "user_rejected")
        @entry.event!("rejected", reason: "user_rejected")
        result(:rejected)
      when "hold"
        @entry.update!(state: "held", reason_code: "user_held")
        @entry.event!("held", reason: "user_held")
        result(:held)
      when "acknowledge_current", "acknowledge_deleted"
        acknowledge
      when "link"
        link(identity, bound)
      else
        create_transaction(draft, identity, bound)
      end
    end

    def create_transaction(draft, identity, bound)
      return result(:held, "identity_already_bound") if bound

      match = Matcher.classify!(@entry)
      reasons = if @action == "auto_apply"
        RuleResolver.automatic_reasons(@entry, draft)
      else
        CandidateValidator.call(draft: draft).reason_codes
      end
      if @action == "approve" && draft.account_id != @entry.import_document.import_source.account_id && !@entry.import_document.import_source.legacy?
        reasons << "source_account_mismatch"
      end
      unless reasons.empty?
        draft.update!(rule_decision: draft.rule_decision.merge("reason_codes" => reasons.uniq))
        if @entry.reason_code.blank? || @entry.classification == "new"
          @entry.update!(state: "held", reason_code: reasons.first)
        end
        return result(:held, reasons.first)
      end
      if %w[approve auto_apply].include?(@action)
        return result(:held) unless @entry.classification == "new" && @entry.state == "pending"
      elsif @action == "distinct"
        return result(:held, "external_id_changed") if @entry.classification == "correction"
      elsif @action == "adopt_revision"
        return result(:held, "not_a_revision") unless identity && @entry.classification == "correction"
        identity.import_entries.where(state: %w[pending held]).where.not(id: @entry.id).order(:id).lock.each do |prior|
          prior.update!(state: "superseded", reason_code: "revision_adopted")
          prior.event!("superseded", details: { "entry_ids" => [@entry.id] })
        end
      end
      transaction = Transaction.create!(draft.transaction_attributes)
      bind!(transaction, "applied", identity)
      @entry.event!("applied", details: { "after" => @entry.target_snapshot,
        "transaction_ids" => match&.transactions&.map(&:id) || [], "entry_ids" => match&.drafts&.map(&:import_entry_id) || [], "selection" => @action, "mode" => @action == "auto_apply" ? "automatic" : "manual",
        "amount" => transaction.amount, "direction" => transaction.direction, "rule_decision" => draft.rule_decision,
        "date_origin" => draft.date_origin, "confirmation" => draft.confirmation_metadata })
      result(:applied)
    end

    def planned_target_failure(draft)
      target = Transaction.where(id: @target_id).lock.first
      return unless target&.planned?

      projection = target.dup
      projection.clear_changes_information
      projection.entry_type = "actual"
      reasons = CandidateValidator.transaction_reasons(transaction: projection, context: :planned_promotion)
      confirmed_move = %w[transfer investment].include?(draft.transaction_kind) && draft.transaction_kind == target.direction &&
        draft.confirmation_metadata["confirmed_values"] == Fingerprint.draft_snapshot(draft) &&
        CandidateValidator.call(draft: draft).reason_codes.empty?
      reasons << "special_transaction" unless (draft.transaction_kind == "normal" && !target.transfer? && !target.investment?) || confirmed_move
      origin = draft.confirmation_metadata["source_kind"]
      move_origin = confirmed_move && %w[transfer charge investment unknown].include?(origin)
      reasons << "special_transaction" if origin.present? && origin != "normal" && !move_origin
      unless reasons.empty?
        Result.new(status: :held, entry: @entry, reason: "invalid_planned_target", reason_codes: reasons.uniq, target_id: target.id)
      end
    end

    def link(identity, bound)
      target = Transaction.where(id: @target_id).lock.first
      return result(:held, "target_missing") unless target
      return result(:held, "identity_target_mismatch") if bound && bound.target_transaction_id != target.id

      before = Fingerprint.transaction_snapshot(target)
      target.update!(entry_type: "actual") if target.planned?
      bind!(target, "linked", identity)
      @entry.event!("linked", details: { "before" => before, "after" => @entry.target_snapshot,
        "target_id" => target.id, "selection" => "differences_confirmed" })
      result(:linked)
    end

    def acknowledge
      return result(:held, "not_a_conflict") unless @entry.state == "conflict"

      target = Transaction.where(id: @entry.target_transaction_id).lock.first
      if @action == "acknowledge_deleted"
        return result(:held, "target_exists") if target

        @entry.update!(state: "deletion_acknowledged", reason_code: "deletion_confirmed")
        @entry.event!("deletion_acknowledged", details: { "target_id" => @entry.target_transaction_id,
          "before" => @entry.target_snapshot, "confirmed_at" => Time.current.iso8601 })
      else
        return result(:conflict, "target_deleted") unless target

        before = @entry.target_snapshot
        @entry.update!(state: "linked", reason_code: "current_confirmed", target_snapshot: Fingerprint.transaction_snapshot(target))
        @entry.event!("acknowledged", details: { "before" => before, "after" => @entry.target_snapshot })
      end
      result(:already_processed)
    end

    def bind!(transaction, state, identity)
      @entry.update!(state: state, target_transaction_id: transaction.id,
        target_snapshot: Fingerprint.transaction_snapshot(transaction), reason_code: "user_#{@action}")
      identity.update!(bound_entry: @entry) if identity && !identity.bound_entry_id
    end

    def result(status, reason = nil)
      Result.new(status: status, entry: @entry, reason: reason || @entry.reason_code)
    end

    def preserve_invalid_edit
      ImportGuard.synchronize do
        @entry = ImportEntry.lock.find(@entry_id)
        return result(:already_processed) if @entry.terminal?
        return result(:conflict) if @entry.state == "conflict"

        draft = @entry.image_import_draft
        begin
          CandidateConfirmation.apply(draft, attributes: @attributes, confirmation: @confirmation,
            confirm_values: @action == "approve").save!
        rescue ActiveRecord::RecordInvalid, ArgumentError
          # 不正なenum等は元の候補を残して修正を案内する。
        end
        reason = %w[legacy_origin_unknown user_held].include?(@entry.reason_code) ? @entry.reason_code : "invalid_transaction"
        @entry.update!(state: "held", reason_code: reason)
        @entry.event!("failed", reason: "invalid_transaction")
        result(:failed)
      end
    end

    def recover_result
      @entry = ImportEntry.find(@entry_id)
      @entry.terminal? ? result(:already_processed) : result(:failed, "connection_lost")
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed
      Result.new(status: :failed, reason: "connection_lost")
    end
  end
end
