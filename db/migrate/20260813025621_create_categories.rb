class CreateCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :categories do |t|
      t.integer :kind, null: false, default: 0
      t.string :name, null: false
      t.integer :monthly_budget
      t.string :note
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :categories, [:kind, :name], unique: true
  end
end
