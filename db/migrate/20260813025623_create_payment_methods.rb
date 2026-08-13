class CreatePaymentMethods < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_methods do |t|
      t.string :name, null: false
      t.string :note
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :payment_methods, :name, unique: true
  end
end
