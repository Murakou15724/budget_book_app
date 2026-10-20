module ImportTargetTracking
  extend ActiveSupport::Concern

  included do
    before_save :acquire_import_guard
    before_destroy :acquire_import_guard
    after_update { Imports::TargetIntegrity.changed!(self) }
    after_destroy { Imports::TargetIntegrity.changed!(self, destroyed: true) }
  end

  private

  def acquire_import_guard
    ImportGuard.synchronize { true }
  end
end
