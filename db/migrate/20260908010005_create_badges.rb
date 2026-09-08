class CreateBadges < ActiveRecord::Migration[7.1]
  def change
    create_table :badges do |t|
      t.integer :required_xp, null: false
      t.string :title, null: false
      t.string :description

      t.timestamps
    end
    add_index :badges, :required_xp, unique: true
  end
end
