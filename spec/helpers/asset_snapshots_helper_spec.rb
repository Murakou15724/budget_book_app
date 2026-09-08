require "rails_helper"

RSpec.describe AssetSnapshotsHelper, type: :helper do
  describe "#asset_trend_svg" do
    def snapshot(recorded_on, balance)
      s = AssetSnapshot.new(recorded_on: recorded_on)
      s.asset_balances.build(balance: balance)
      def s.total_balance
        asset_balances.sum(&:balance)
      end
      s
    end

    it "点数が多い場合は、点が密集しないようmin-widthを付けて横スクロールできるようにする" do
      snapshots = 40.times.map { |i| snapshot(Date.new(2028, 1, 1) + i, 100_000 + i * 1000) }

      html = helper.asset_trend_svg(snapshots)

      expect(html).to include("min-width: #{40 * AssetSnapshotsHelper::MIN_POINT_SPACING}px;")
    end

    it "点数が少なければmin-widthも小さい" do
      snapshots = [snapshot(Date.new(2028, 1, 1), 100_000), snapshot(Date.new(2028, 2, 1), 110_000)]

      html = helper.asset_trend_svg(snapshots)

      expect(html).to include("min-width: #{2 * AssetSnapshotsHelper::MIN_POINT_SPACING}px;")
    end
  end
end
