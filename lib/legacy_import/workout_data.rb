module LegacyImport
  # 旧Excel筋トレ管理「筋トレ管理_2026.xlsx」(Menu_Master, Workout_Log)からの移行データ。
  # docs/筋トレ記録_要件定義書.md 6章の移行方針に基づき、状態(実施/軽め/休み)が
  # 明示的に入っている行のみを取り込む(空欄の日は未記録として扱い取り込まない)。
  # XPはExcel側の計算済みの値をそのまま保存する(計算式の見直しで過去実績が変動するのを防ぐため)。
  module WorkoutData
    EXERCISES = [
      { name: "腕立て伏せ", body_part: "胸・腕", default_sets: 3, default_reps: 10, default_weight_kg: 0, default_duration_min: 10, memo: "自重。できなければ膝つきで可" },
      { name: "スクワット", body_part: "脚", default_sets: 3, default_reps: 15, default_weight_kg: 0, default_duration_min: 10, memo: "フォーム優先" },
      { name: "プランク", body_part: "体幹", default_sets: 3, default_reps: 1, default_weight_kg: 0, default_duration_min: 5, memo: "回数=セット内の本数で入力" },
      { name: "腹筋", body_part: "体幹", default_sets: 3, default_reps: 15, default_weight_kg: 0, default_duration_min: 8 },
      { name: "ダンベルカール", body_part: "腕", default_sets: 3, default_reps: 10, default_weight_kg: 5, default_duration_min: 10, memo: "重量は片手目安" },
      { name: "ショルダープレス", body_part: "肩", default_sets: 3, default_reps: 10, default_weight_kg: 5, default_duration_min: 10 },
      { name: "ランニング", body_part: "有酸素", default_sets: 1, default_reps: 1, default_weight_kg: 0, default_duration_min: 20, memo: "時間分を中心に記録" },
      { name: "ストレッチ", body_part: "回復", default_sets: 1, default_reps: 1, default_weight_kg: 0, default_duration_min: 10, memo: "軽め扱いでも可" }
    ].freeze

    WORKOUT_DAYS = [
      { date: "2026-06-16", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 30, rpe: 5, xp: 87, mood: "良い", memo: "今日は目標設定面談の完了！筋トレ表の作成完了！" },
      { date: "2026-06-17", status: "実施", menu: "スクワット", sets: 2, reps: 180, weight: 0, duration: 15, rpe: 5, xp: 73, mood: "普通", memo: "明日が終われば金曜日は在宅！" },
      { date: "2026-06-18", status: "休み" },
      { date: "2026-06-19", status: "休み" },
      { date: "2026-06-20", status: "休み" },
      { date: "2026-06-21", status: "休み" },
      { date: "2026-06-22", status: "休み" },
      { date: "2026-06-23", status: "実施", menu: "腹筋", sets: 7, reps: 20, weight: 0, duration: 26, rpe: 6, xp: 89, mood: "良い", memo: "マジでここから頑張ろう。" },
      { date: "2026-06-24", status: "実施", menu: "スクワット", sets: 5, reps: 50, weight: 0, duration: 25, rpe: 5, xp: 88, mood: "良い", memo: "いったん2日連続ナイス。早めに料理アプリ完成させよう" },
      { date: "2026-06-25", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 20, rpe: 5, xp: 67, mood: "良い", memo: "明日は在宅！そして夜から鷹觜と会えるぜえ！！！" },
      { date: "2026-06-26", status: "休み" },
      { date: "2026-06-27", status: "休み" },
      { date: "2026-06-28", status: "休み" },
      { date: "2026-06-29", status: "実施", menu: "腹筋", sets: 5, reps: 15, weight: 0, duration: 30, rpe: 5, xp: 89, mood: "良い", memo: "プロテイン買いなおしたぜ！今週末はボドゲと神宮！" },
      { date: "2026-06-30", status: "実施", menu: "スクワット", sets: 2, reps: 360, weight: 0, duration: 20, rpe: nil, xp: 76, mood: "良い", memo: "ここに書くことが思いつかないのやばない？明日は出社…" },
      { date: "2026-07-01", status: "休み" },
      { date: "2026-07-02", status: "実施", menu: "腕立て伏せ", sets: 5, reps: 10, weight: 0, duration: 15, rpe: 5, xp: 58, mood: "最高", memo: "明日は在宅！今週末はけんぞーとはまさん！" },
      { date: "2026-07-03", status: "休み" },
      { date: "2026-07-04", status: "休み" },
      { date: "2026-07-05", status: "休み" },
      { date: "2026-07-06", status: "実施", menu: "ランニング", sets: 1, reps: 1, weight: 0, duration: 20, rpe: 5, xp: 65, mood: "普通", memo: "こりゃはまさんあかんかったな…" },
      { date: "2026-07-07", status: "休み" },
      { date: "2026-07-08", status: "休み" },
      { date: "2026-07-09", status: "休み" },
      { date: "2026-07-10", status: "休み" },
      { date: "2026-07-11", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 20, rpe: 4, xp: 62, mood: "普通", memo: "なんか返信少なくね？どうしたらええの？" },
      { date: "2026-07-12", status: "実施", menu: "腹筋", sets: 4, reps: 10, weight: 0, duration: 15, rpe: 5, xp: 57, mood: "良い", memo: "また一週間頑張りましょう！" },
      { date: "2026-07-13", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 20, rpe: 5, xp: 67, mood: "良い", memo: "仕事が詰まってないので、早く帰れてて良い感じ" },
      { date: "2026-07-14", status: "実施", menu: "スクワット", sets: 4, reps: 20, weight: 0, duration: 20, rpe: 5, xp: 69, mood: "良い", memo: "もっと人に聞けよ！！！ってことですね。" },
      { date: "2026-07-15", status: "休み", memo: "チーム飲み会" },
      { date: "2026-07-16", status: "休み", memo: "遅くまで飲んでたので、みんなで在宅" },
      { date: "2026-07-17", status: "休み", memo: "普通に在宅。夜から幕張へドライブ、一蘭を食べて帰宅。" },
      { date: "2026-07-18", status: "休み", memo: "フットサル！帰りにまたラーメン笑" },
      { date: "2026-07-19", status: "実施", menu: "腹筋", sets: 4, reps: 10, weight: 0, duration: 20, rpe: 4, xp: 62, mood: "良い", memo: "今日はだらだら。アプリの修正できてない。" },
      { date: "2026-07-20", status: "休み" },
      { date: "2026-07-21", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 15, rpe: 4, xp: 52, mood: "良い" },
      { date: "2026-07-22", status: "実施", menu: "腕立て伏せ", sets: 6, reps: 10, weight: 0, duration: 30, rpe: 6, xp: 93, mood: "最高", memo: "仕事少ないので明日は在宅でゆっくりしましょ。" },
      { date: "2026-07-23", status: "実施", menu: "腹筋", sets: 5, reps: 10, weight: 0, duration: 30, rpe: 6, xp: 93, mood: "最高", memo: "明日はLaiblitzNightとわたくしの23歳の誕生日と給料日！" },
      { date: "2026-07-24", status: "休み" },
      { date: "2026-07-25", status: "休み" },
      { date: "2026-07-26", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 15, rpe: 3, xp: 47, mood: "良い" },
      { date: "2026-07-28", status: "実施", menu: "腹筋", sets: 5, reps: 10, weight: 0, duration: 25, rpe: 5, xp: 78, mood: "良い" },
      { date: "2026-08-18", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 30, rpe: 6, xp: 92, mood: "良い", memo: "阪神が佐藤輝と大山の二者連続ホームランでサヨナラ勝ち！！！" },
      { date: "2026-08-24", status: "実施", menu: "腕立て伏せ", sets: 5, reps: 10, weight: 0, duration: 30, rpe: 7, xp: 98, mood: "良い", memo: "ついに…！！！！！！" },
      { date: "2026-08-25", status: "実施", menu: "腹筋", sets: 5, reps: 20, weight: 0, duration: 25, rpe: 7, xp: 90, mood: "良い", memo: "今のところ仕事が少ない…暇だ…これでええんか？" },
      { date: "2026-08-26", status: "実施", menu: "スクワット", sets: 4, reps: 10, weight: 0, duration: 25, rpe: 6, xp: 82, mood: "最高", memo: "9月からTYSも担当するらしいです！" },
      { date: "2026-09-01", status: "実施", menu: "腕立て伏せ", sets: 4, reps: 10, weight: 0, duration: 20, rpe: 5, xp: 67, mood: "良い", memo: "水族館楽しかったね！（家計簿アプリの本格運用開始！）" }
    ].freeze

    STATUS_MAP = { "実施" => "worked_out", "軽め" => "light", "休み" => "rest" }.freeze

    def self.import!
      exercise_ids = EXERCISES.each_with_object({}) do |attrs, memo|
        exercise = Exercise.find_or_create_by!(name: attrs[:name]) do |e|
          e.body_part = attrs[:body_part]
          e.default_sets = attrs[:default_sets]
          e.default_reps = attrs[:default_reps]
          e.default_weight_kg = attrs[:default_weight_kg]
          e.default_duration_min = attrs[:default_duration_min]
          e.memo = attrs[:memo]
        end
        memo[attrs[:name]] = exercise.id
      end

      entries_created = 0

      WORKOUT_DAYS.each do |attrs|
        day = WorkoutDay.find_or_initialize_by(date: Date.parse(attrs[:date]))
        next if day.persisted? && day.workout_entries.exists?

        if day.new_record?
          day.status = STATUS_MAP.fetch(attrs[:status])
          day.mood = attrs[:mood]
          day.memo = attrs[:memo]
        end

        # 「実施」の日は種目を1つ以上要求するバリデーションがあるため、
        # 保存前に(日のレコードと同じトランザクションで)エントリーを組み立てておく。
        if attrs[:menu]
          entry = day.workout_entries.build(
            exercise_id: exercise_ids.fetch(attrs[:menu]),
            sets: attrs[:sets],
            reps: attrs[:reps],
            weight_kg: attrs[:weight],
            duration_min: attrs[:duration],
            rpe: attrs[:rpe]
          )
          entry.xp = attrs[:xp]
          entry.skip_xp_calculation = true
          entries_created += 1
        end

        day.save!
      end

      puts "筋トレ記録を投入しました: 種目#{EXERCISES.size}件 / 日次記録#{WORKOUT_DAYS.size}件 / エントリー#{entries_created}件"
    end
  end
end
