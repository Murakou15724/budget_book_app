require "rails_helper"

RSpec.describe Badge, type: :model do
  before do
    Badge.create!(required_xp: 0, title: "Lv1: 入門者")
    Badge.create!(required_xp: 250, title: "Lv2: 習慣化見習い")
    Badge.create!(required_xp: 1500, title: "Lv5: 鉄の意志")
  end

  describe ".for_xp" do
    it "しきい値以下で最大の称号を返す" do
      expect(Badge.for_xp(1801).title).to eq("Lv5: 鉄の意志")
      expect(Badge.for_xp(100).title).to eq("Lv1: 入門者")
    end
  end

  describe ".next_for_xp" do
    it "次のしきい値の称号を返す" do
      expect(Badge.next_for_xp(100).title).to eq("Lv2: 習慣化見習い")
    end

    it "最高位を超えていればnil" do
      expect(Badge.next_for_xp(9999)).to be_nil
    end
  end

  describe ".level_for_xp" do
    it "しきい値を何番目まで満たしているかをレベル番号として返す(称号のしきい値に一本化)" do
      expect(Badge.level_for_xp(1801)).to eq(3)
      expect(Badge.level_for_xp(0)).to eq(1)
    end
  end
end
