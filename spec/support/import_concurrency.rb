require "timeout"

module ImportConcurrency
  def concurrent(*operations)
    ready = Queue.new
    release = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          Timeout.timeout(15) { release.pop }
          operation.call
        end
      end
    end
    Timeout.timeout(15) { operations.size.times { ready.pop } }
    operations.size.times { release << true }
    threads.map { |thread| Timeout.timeout(20) { thread.value } }
  ensure
    threads&.each do |thread|
      next unless thread.alive?

      thread.kill
      thread.join
    end
  end

  def record_fixture_ids
    skip "並行検証は専用使い捨てDBでのみ実行します" unless ActiveRecord::Base.connection_db_config.database == "budget_book_app_test_67"

    @fixture_ids = cleanup_models.to_h { |model| [model, model.pluck(:id)] }
  end

  def cleanup_fixture_ids
    return unless @fixture_ids

    ImportIdentity.where.not(id: @fixture_ids.fetch(ImportIdentity)).update_all(bound_entry_id: nil)
    ImportEntry.where.not(id: @fixture_ids.fetch(ImportEntry)).update_all(reference_entry_id: nil)
    cleanup_models.each { |model| model.where.not(id: @fixture_ids.fetch(model)).delete_all }
  end

  def cleanup_models
    [ImportEvent, ImageImportDraft, ImportEntry, ImportIdentity, ImportDocument, ImportSource,
      Transaction, Category, PaymentMethod, Account, Setting]
  end
end
