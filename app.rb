require 'sinatra'
require 'sqlite3'
require 'time'

# ① ポートとバインドの設定（Render用）
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

# ② 日本時間の設定
ENV['TZ'] = 'Asia/Tokyo'

# ③ データベースを準備する関数（起動時に実行）
def setup_db
  db = SQLite3::Database.new "sns_v2.db"
  # 初期テーブル作成
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_name TEXT,
      drug_name TEXT,
      likes INTEGER DEFAULT 0,
      message TEXT,
      parent_id INTEGER DEFAULT -1,
      created_at TEXT,
      title TEXT
    );
  SQL
  # カラム（title）追加のケア
  begin
    db.execute("ALTER TABLE posts ADD COLUMN title TEXT")
  rescue
    # 既にある場合は何もしない
  end
  db.close
end

setup_db

# データベースに接続して処理し、自動で閉じるためのヘルパー
def query
  db = SQLite3::Database.new "sns_v2.db"
  yield db
ensure
  db.close if db
end

# --- デザイン系（変更なし） ---

def header_menu
  "
  <style>
    body { font-family: 'Helvetica Neue', Arial, sans-serif; margin: 0; background-color: #f4f7f9; color: #333; }
    .container { max-width: 1000px; margin: 0 auto; padding: 20px; display: flex; gap: 20px; }
    .main-content { flex: 3; }
    .sidebar { flex: 1; background: white; padding: 20px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.05); height: fit-content; }
    nav { background: #0077b6; padding: 15px 40px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    nav a { color: white; text-decoration: none; margin-right: 25px; font-weight: bold; }
    .post-card { background: white; padding: 20px; border-radius: 12px; margin-bottom: 15px; box-shadow: 0 2px 5px rgba(0,0,0,0.05); border-left: 6px solid #ccc; transition: 0.2s; }
    .post-card:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
    .cat-処方介入 { border-left-color: #4caf50; }
    .cat-インシデント { border-left-color: #f44336; }
    .cat-他職種連携 { border-left-color: #ff9800; }
    .cat-薬品相談 { border-left-color: #2196f3; }
    .cat-保険関連 { border-left-color: #9c27b0; }
    .tag { padding: 4px 10px; border-radius: 20px; font-size: 0.75em; color: white; font-weight: bold; margin-right: 8px; }
    .btn-submit { background: #0077b6; color: white; border: none; padding: 15px 20px; border-radius: 8px; cursor: pointer; width: 100%; font-size: 1.1em; font-weight: bold; }
    input, select, textarea { width: 100%; padding: 12px; margin-top: 5px; margin-bottom: 20px; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; font-size: 1em; }
    label { font-weight: bold; color: #444; }
  </style>
  <nav>
    <a href='/'>🏠 ホーム</a>
    <a href='/post_new'>✍️ 投稿する</a>
    <a href='/search_page'>🔍 検索</a>
  </nav>
  <div class='container'>
    <div class='main-content'>
  "
end

def sidebar_content
  "
    </div> <div class='sidebar'>
      <h3 style='color:#0077b6; margin-top:0;'>📢 創設者より</h3>
      <p style='font-size: 0.9em; line-height: 1.6;'>
        <strong>かたばみ</strong>です。<br>
        薬剤師の知恵を資産に変える場所へようこそ！
      </p>
      <a href='/about_message' style='display:inline-block; color:#0077b6; font-size:0.95em; font-weight:bold; text-decoration:none; border: 1px solid #0077b6; padding: 5px 10px; border-radius: 5px;'>👉 全ての薬剤師へ</a>
      <hr style='margin: 20px 0; border: 0; border-top: 1px solid #eee;'>
      <h4 style='font-size: 0.9em; margin-bottom: 10px;'>📜 利用ルール</h4>
      <ul style='font-size: 0.85em; padding-left: 20px; line-height: 1.8; color: #555;'>
        <li>個人情報は厳禁！</li>
        <li>前向きな意見交換を</li>
        <li>保険ルールも共有しよう</li>
        <li>自信を持って発信！</li>
      </ul>
    </div>
  </div> "
end

def render_post_item(row)
  msg_str = row[4].to_s
  cat_name = msg_str.include?(']') ? msg_str.split(']')[0].delete('[') : "未分類"
  tag_color = case cat_name
              when "処方介入" then "#4caf50"
              when "インシデント" then "#f44336"
              when "他職種連携" then "#ff9800"
              when "薬品相談" then "#2196f3"
              when "保険関連" then "#9c27b0"
              else "#0077b6"
              end
  "<div class='post-card cat-#{cat_name}'>
    <div style='display:flex; justify-content:space-between; align-items:center;'>
      <span class='tag' style='background:#{tag_color};'>#{cat_name}</span>
      <small style='color:gray;'>#{row[6]}</small>
    </div>
    <h2 style='margin: 12px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:#333;'>#{row[7] || '無題の投稿'}</a></h2>
    <div style='font-size:0.95em; color:#666;'>💊 対象薬: <strong>#{row[2]}</strong> | 👨‍⚕️ 投稿者: #{row[1]}</div>
  </div>"
end

# --- 各ルート（DB接続を query メソッド経由に修正） ---

get '/' do
  html = header_menu + "<h1 style='margin-top:0;'>📋 最新の知恵袋</h1>"
  query do |db|
    posts = db.execute("SELECT * FROM posts WHERE parent_id = -1 ORDER BY id DESC")
    posts.each { |row| html += render_post_item(row) }
  end
  html + sidebar_content
end

get '/about_message' do
  html = header_menu + "
    <div style='background:white; padding:45px; border-radius:16px; line-height:2.0; box-shadow: 0 10px 30px rgba(0,0,0,0.08);'>
      <h1 style='color:#0077b6; border-bottom:4px solid #0077b6; padding-bottom:15px; margin-bottom:35px; text-align:center;'>全ての薬剤師へ</h1>
      <p style='font-size:1.3em; font-weight:bold; color:#0077b6; text-align:center; margin-bottom:40px;'>「その『独り言』を、未来を変える力に変えませんか？」</p>
      <section style='margin-bottom:35px;'><h2 style='font-size:1.15em; color:#333; border-left:5px solid #0077b6; padding-left:15px; margin-bottom:15px;'>薬局に溢れる、価値ある「独り言」</h2><p>処方箋を手に取ったとき、私たちはいつも心の中で「独り言」を言っています。<br>「この用法を変えれば、患者さんの負担がもっと減るのに」「この薬、実はもっと減らせるんじゃないか？」「この併用は避けたほうがいい。もっと良い選択肢があるはずだ」</p><p>それは、あなたが患者さんのために真剣に考え、悩み、導き出した<strong>「臨床の直感」</strong>です。でも、その多くは誰に共有されることもなく、キーボードを叩く音と共に消えていってしまいます。</p></section>
      <section style='margin-bottom:35px; background:#f0f9ff; padding:25px; border-radius:12px;'><h2 style='font-size:1.15em; color:#0077b6; margin-top:0;'>薬の専門家として、揺るぎない自信を</h2><p>薬剤師は、薬に関しては医師以上に深く、緻密な知識を持っています。私たちが持っているエビデンスと思考プロセスには、もっと大きな価値がある。だからこそ、自分たちの判断に、もっと自信を持ってほしいのです。</p><p>ここであなたの思考を共有してください。「自分だけが感じていた違和感」が、実は「みんなが感じていた課題」だと知ることで、それは確信に変わります。そして誰かの新しい発見が、あなたの臨床をさらに深化させるはずです。</p></section>
      <section style='margin-bottom:40px;'><h2 style='font-size:1.15em; color:#333; border-left:5px solid #0077b6; padding-left:15px; margin-bottom:15px;'>臨床の主役へ</h2><p>この場所で発信し、共有し、互いに高め合うことで、確固たる自信をつけてほしい。<br>その自信を持って、医師や他職種、誠に患者さんが待つ現場へ戻ってください。</p><p style='font-weight:bold;'>私たちはもっと、臨床に影響力を与えられる存在になれる。<br>あなたの発信が、明日の薬剤師の立ち位置を変え、誰かの命を救います。</p></section>
      <div style='text-align:right; margin-top:50px; border-top:1px solid #eee; padding-top:20px;'><p style='margin-bottom:5px; font-size:1.1em;'>創設者：<strong>かたばみ</strong></p><small style='color:gray;'>2026年1月12日 始動</small></div>
      <div style='text-align:center; margin-top:40px;'><a href='/' style='display:inline-block; padding:15px 40px; background:#0077b6; color:white; text-decoration:none; border-radius:50px; font-weight:bold; box-shadow:0 4px 15px rgba(0,119,182,0.3);'>知恵の共有を始める</a></div>
    </div>"
  html + sidebar_content
end

get '/post_new' do
  html = header_menu + "
    <h1>✍️ 知恵を記録する</h1>
    <div style='background:white; padding:30px; border-radius:12px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);'>
      <form action='/post' method='post'>
        <label>投稿者を選択:</label><select name='user_name'><option value='かたばみパパ'>👨‍⚕️ かたばみパパ</option><option value='ママ'>👩‍⚕️ ママ</option><option value='薬局スタッフ'>🧑‍⚕️ 薬局スタッフ</option></select>
        <label>カテゴリ:</label><select name='category'><option value='処方介入'>処方介入事例</option><option value='インシデント'>インシデントレポート</option><option value='他職種連携'>他職種連携事例</option><option value='薬品相談'>薬品名からの相談</option><option value='保険関連'>保険関連</option></select>
        <label>タイトル:</label><input type='text' name='title' placeholder='例：高齢者のポリファーマシーへの介入' required>
        <label>薬品名:</label><input type='text' name='drug_name' placeholder='例：アムロジピン' required>
        <label>内容:</label><textarea name='message' style='height:200px;' placeholder='どのような思考で介入したか、独り言を形にしてください...' required></textarea>
        <button type='submit' class='btn-submit'>🚀 投稿して共有する</button>
      </form>
    </div>"
  html + sidebar_content
end

get '/post/:id' do
  post = nil
  query { |db| post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first }
  return "投稿が見つかりませんでした。" unless post
  
  safe_msg = post[4].to_s.gsub("\n", "<br>")
  html = header_menu + "
    <div style='background:white; padding:35px; border-radius:12px;'>
      <a href='/' style='color:#0077b6; text-decoration:none; font-weight:bold;'>← ホームに戻る</a>
      <h1 style='margin-top:25px; border-bottom:3px solid #0077b6; padding-bottom:12px;'>#{post[7]}</h1>
      <div style='display:flex; justify-content:space-between; color:gray; margin-bottom:20px;'><span>👨‍⚕️ 投稿者: #{post[1]}</span><span>📅 #{post[6]}</span></div>
      <h3 style='color:#0077b6; background:#f0f7fa; padding:10px; border-radius:5px;'>💊 薬品名: #{post[2]}</h3>
      <div style='font-size:1.15em; line-height:1.8; background:#fff; padding:10px; border: 1px solid #eee; border-radius:8px; margin-top:20px;'>#{safe_msg}</div>
      <form action='/like_detail/#{post[0]}' method='post' style='margin-top:30px; text-align:center;'>
        <button type='submit' style='background:#ffeded; border:1px solid #ffc1c1; color:#f44336; padding:12px 30px; border-radius:30px; cursor:pointer; font-weight:bold; font-size:1.1em;'>❤️ 役に立った！ (#{post[3]})</button>
      </form>
    </div>"
  html + sidebar_content
end

get '/search_page' do
  search_word = params[:search]
  posts = []
  if search_word
    query { |db| posts = db.execute("SELECT * FROM posts WHERE (message LIKE ? OR title LIKE ? OR drug_name LIKE ?) AND parent_id = -1", ["%#{search_word}%", "%#{search_word}%", "%#{search_word}%"]) }
  end
  
  html = header_menu + "
    <h1>🔍 検索</h1>
    <div style='background:white; padding:25px; border-radius:12px; margin-bottom:25px;'>
      <form action='/search_page' method='get' style='display:flex; gap:10px; margin:0;'>
        <input type='text' name='search' value='#{search_word}' placeholder='キーワードを入力...' style='margin:0;'>
        <button type='submit' class='btn-submit' style='width:120px; height:46px;'>検索</button>
      </form>
    </div>"
  
  if search_word
    html += "<h3>「#{search_word}」の検索結果: #{posts.size}件</h3>"
    posts.each { |row| html += render_post_item(row) }
  end
  html + sidebar_content
end

post '/post' do
  current_time = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  full_msg = "[#{params[:category]}] #{params[:message]}"
  query do |db|
    db.execute("INSERT INTO posts (user_name, drug_name, message, parent_id, title, created_at) VALUES (?, ?, ?, ?, ?, ?)", 
               [params[:user_name], params[:drug_name], full_msg, -1, params[:title], current_time])
  end
  redirect '/'
end

post '/like_detail/:id' do
  query { |db| db.execute("UPDATE posts SET likes = likes + 1 WHERE id = ?", [params[:id]]) }
  redirect "/post/#{params[:id]}"
end