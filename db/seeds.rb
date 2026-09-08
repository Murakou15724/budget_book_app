# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# 筋トレ記録: 称号マスタ(Excel「Badges」シートの初期値)
[
  { required_xp: 0, title: "Lv1: 入門者", description: "まずは記録開始" },
  { required_xp: 250, title: "Lv2: 習慣化見習い", description: "週に数回できている" },
  { required_xp: 500, title: "Lv3: 継続者", description: "記録が積み上がっている" },
  { required_xp: 1000, title: "Lv4: 鍛錬者", description: "筋トレが生活に入ってきた" },
  { required_xp: 1500, title: "Lv5: 鉄の意志", description: "休んでも戻れる状態" },
  { required_xp: 2500, title: "Lv6: ルーティン職人", description: "安定して継続" },
  { required_xp: 4000, title: "Lv7: 筋トレ上級者", description: "高い継続力" },
  { required_xp: 6000, title: "Lv8: Daily Quest Master", description: "完全に習慣化" },
].each do |attrs|
  Badge.find_or_create_by!(required_xp: attrs[:required_xp]) do |badge|
    badge.title = attrs[:title]
    badge.description = attrs[:description]
  end
end

# 筋トレ記録: 設定値(Excel「Dashboard」シートの初期値を踏襲)
setting = WorkoutSetting.current
setting.update!(
  start_date: Date.new(2026, 6, 16),
  weekly_goal_count: 5,
  weekly_goal_xp: 300,
  current_goal_text: "毎日、最低1種目だけでも記録する"
) if setting.current_goal_text.blank?
