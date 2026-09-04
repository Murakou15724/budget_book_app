module TransactionsHelper
  def transaction_amount_css_class(transaction)
    case transaction.direction
    when "income" then "is-income"
    when "expense" then "is-expense"
    else "is-transfer"
    end
  end

  def transaction_amount_sign(transaction)
    case transaction.direction
    when "income" then "+"
    when "expense" then "-"
    else "→"
    end
  end
end
