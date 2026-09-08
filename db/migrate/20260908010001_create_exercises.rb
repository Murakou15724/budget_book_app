class CreateExercises < ActiveRecord::Migration[7.1]
  def change
    create_table :exercises do |t|
      t.string :name, null: false
      t.string :body_part
      t.integer :default_sets
      t.integer :default_reps
      t.decimal :default_weight_kg, precision: 5, scale: 1
      t.integer :default_duration_min
      t.text :memo

      t.timestamps
    end
    add_index :exercises, :name, unique: true
  end
end
