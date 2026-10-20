class ImportGuard < ApplicationRecord
  # schema:loadはデータを作らないため、毎回unique制約のある行を確保する。
  def self.synchronize
    transaction do
      guard = create_or_find_by!(name: "ledger")
      guard.lock!
      yield
    end
  end
end
