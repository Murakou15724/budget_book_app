class AddImageImportRequiresApprovalToSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :settings, :image_import_requires_approval, :boolean, null: false, default: true
  end
end
