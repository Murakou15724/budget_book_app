module Imports
  module TargetIntegrity
    module_function

    def check!(entry)
      return entry if %w[deletion_acknowledged rejected superseded].include?(entry.state)
      return entry unless entry.target_transaction_id
      return entry if entry.state == "conflict"

      target = Transaction.where(id: entry.target_transaction_id).lock.first
      if target.nil? || !Fingerprint.transaction_matches?(target, entry.target_snapshot)
        conflict!(entry, target)
      end
      entry
    end

    def conflict!(entry, target)
      return if entry.state == "deletion_acknowledged"

      before = entry.target_snapshot
      after = target && Fingerprint.transaction_snapshot(target)
      entry.update!(state: "conflict", reason_code: target ? "target_changed" : "target_deleted")
      entry.event!("conflict", reason: entry.reason_code,
        details: { "before" => before, "after" => after, "target_id" => entry.target_transaction_id })
    end

    def changed!(target, destroyed: false)
      ImportEntry.where(target_transaction_id: target.id, state: %w[applied linked]).order(:id).lock.each do |entry|
        next if !destroyed && Fingerprint.transaction_matches?(target, entry.target_snapshot)

        conflict!(entry, destroyed ? nil : target)
      end
    end

    def refresh!(entries)
      ImportGuard.synchronize do
        entries.map(&:effective_entry).uniq(&:id).sort_by(&:id).each do |entry|
          entry.reload.lock!
          check!(entry)
        end
      end
    end
  end
end
