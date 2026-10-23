module ImportConfigurationGuard
  extend ActiveSupport::Concern

  included do
    before_save :lock_import_configuration, prepend: true
    before_destroy :lock_import_configuration, prepend: true
  end

  private

  def lock_import_configuration
    ImportGuard.synchronize { true }
  end
end
