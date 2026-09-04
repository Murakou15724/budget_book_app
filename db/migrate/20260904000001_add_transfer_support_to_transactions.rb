class AddTransferSupportToTransactions < ActiveRecord::Migration[7.1]
  def change
    # 振替(transfer)・投資(investment)取引はカテゴリ分類になじまないため、
    # 「支出」の分類を目的としたcategory_idの必須制約を緩める。
    change_column_null :transactions, :category_id, true
    change_column_null :quick_entry_templates, :category_id, true

    # 振替・投資の移動先口座(任意)。未入力でも記録できるが、入力すると
    # 資産スナップショットとの整合性チェック(AccountReconciliation)に使われる。
    add_reference :transactions, :to_account, foreign_key: { to_table: :accounts }, null: true
    add_reference :quick_entry_templates, :to_account, foreign_key: { to_table: :accounts }, null: true
  end
end
