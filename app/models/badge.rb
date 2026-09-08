class Badge < ApplicationRecord
  validates :required_xp, presence: true, uniqueness: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :title, presence: true

  scope :ordered, -> { order(:required_xp) }

  def self.for_xp(xp)
    ordered.where("required_xp <= ?", xp).last
  end

  def self.next_for_xp(xp)
    ordered.where("required_xp > ?", xp).first
  end

  # しきい値を昇順に並べたときの何番目かをそのままレベル番号にする
  # (Excel版は現在Lvと称号のしきい値が別ロジックでズレていたため、ここで一本化する)。
  def self.level_for_xp(xp)
    ordered.where("required_xp <= ?", xp).count
  end
end
