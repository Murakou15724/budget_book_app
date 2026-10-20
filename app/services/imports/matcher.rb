module Imports
  class Matcher
    Match = Struct.new(:classification, :reason_code, :transactions, :drafts, keyword_init: true)

    def self.call(entry:, draft:)
      new(entry, draft).call
    end

    def initialize(entry, draft)
      @entry, @draft = entry, draft
    end

    def call
      transactions, drafts = comparison_set
      reason = nil
      classification = "new"
      identity = @entry.import_identity
      if identity && identity.import_entries.where(reference_entry_id: nil).where.not(id: @entry.id).lock.exists?
        classification, reason = "correction", "external_id_changed"
      elsif %w[legacy_origin_unknown user_held].include?(@entry.reason_code)
        classification, reason = "hold", @entry.reason_code
      elsif transactions.any? || drafts.any?
        classification, reason = "hold", "similar_candidates"
      elsif !Transaction.new(@draft.transaction_attributes).valid?
        classification, reason = "hold", "invalid_transaction"
      elsif @entry.import_document.import_source.account_id.present? &&
          @draft.account_id != @entry.import_document.import_source.account_id
        classification, reason = "hold", "source_account_mismatch"
      end
      Match.new(classification: classification, reason_code: reason, transactions: transactions, drafts: drafts)
    end

    def comparison_set
      return [[], []] unless @draft.date && @draft.account_id && @draft.amount

      attributes = { account_id: @draft.account_id, direction: @draft.direction, amount: @draft.amount,
        date: (@draft.date - 7)..(@draft.date + 7) }
      transactions = Transaction.where(attributes).includes(:category, :payment_method, :account, :to_account).order(:id).lock.to_a
      drafts = ImageImportDraft.pending.where(attributes).where.not(id: @draft.id).order(:id).lock.to_a
      [transactions, drafts]
    end

    def self.classify!(entry)
      return if entry.reference_entry_id || entry.terminal? || entry.state == "conflict"

      match = call(entry: entry, draft: entry.image_import_draft)
      entry.update!(classification: match.classification, state: match.classification == "new" ? "pending" : "held", reason_code: match.reason_code)
      entry.event!("classified", reason: match.reason_code, details: { "transaction_ids" => match.transactions.map(&:id), "entry_ids" => match.drafts.map(&:import_entry_id) })
      match
    end
  end
end
