require 'sinatra'
require 'sqlite3'
require 'time'

set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
ENV['TZ'] = 'Asia/Tokyo'

# データベース準備（削除用パスワード用のカラム password を追加）
def setup_db
  db = SQLite3::Database.new "sns_v2.db"
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_name TEXT,
      drug_name TEXT,
      likes INTEGER DEFAULT 0,
      message TEXT,
      parent_id INTEGER DEFAULT -1,
      created_at TEXT,
      title TEXT,
      password TEXT
    );
  SQL
  # 既存のDBにpasswordカラムがない場合のための追加処理
  begin
    db.execute("ALTER TABLE posts ADD COLUMN password TEXT")
  rescue
  end
  db.close
end

setup_db

def query
  db = SQLite3::Database.new "sns_v2.db"
  yield db
ensure
  db.close if db
end

# --- デザイン（削除ボタン用のスタイルを追加） ---
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
    .tag { padding: 4px 10px; border-radius: 20px; font-size: 0.75em; color: white; font-weight: bold; margin-right: 8px; }
    .btn-submit { background: #0077b6; color: white; border: none; padding: 12px 20px; border-radius: 8px; cursor: pointer; width: 100%; font-size: 1.1em; font-weight: bold; }
    .btn-delete { background: #ff4d4d; color: white; border: none; padding: 8px 15px; border-radius: 5px; cursor: pointer; font-size: 0.9em; text-decoration: none; }
    input, select, textarea { width: 100%; padding: 12px; margin-top: 5px; margin-bottom: 20px; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
    label { font-weight: bold; color: #444; }
  </style>
  <nav><a href='/'>🏠 ホーム</a><a href='/post_new'>✍️ 投稿する</a><a href='/search_page'>🔍 検索</a></nav>
  <div class='container'><div class='main-content'>
  "
end

def sidebar_content
  "</div> <div class='sidebar'>
    <h3 style='color:#0077b6; margin-top:0;'>📢 創設者より</h3>
    <p style='font-size: 0.9em;'><strong>かたばみ</strong>です。知恵を資産に変えましょう！</p>
    <a href='/about_message' style='text-decoration:none; color:#0077b6; font-weight:bold;'>👉 メッセージを読む</a>
  </div></div>"
end

def render_post_item(row)
  "<div class='post-card'>
    <div style='display:flex; justify-content:space-between;'><span class='tag' style='background:#0077b6;'>知恵</span><small>#{row[6]}</small></div>
    <h2 style='margin:12px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:#333;'>#{row[7] || '無題'}</a></h2>
    <div style='font-size:0.9em; color:#666;'>💊 #{row[2]} | 👨‍⚕️ #{row[1]}</div>
  </div>"
end

# --- ルート設定 ---

get '/' do
  html = header_menu + "<h1>📋 最新の知恵袋</h1>"
  query { |db| db.execute("SELECT * FROM posts WHERE parent_id = -1 ORDER BY id DESC").each { |r| html += render_post_item(r) } }
  html + sidebar_content
end

get '/post_new' do
  html = header_menu + "
    <h1>✍️ 投稿する</h1>
    <form action='/post' method='post'>
      <label>投稿者:</label><select name='user_name'><option>かたばみパパ</option><option>ママ</option></select>
      <label>タイトル:</label><input type='text' name='title' required>
      <label>薬品名:</label><input type='text' name='drug_name' required>
      <label>内容:</label><textarea name='message' style='height:150px;' required></textarea>
      <label style='color:#d9534f;'>🔑 削除用パスワード（半角英数）:</label>
      <input type='password' name='password' placeholder='削除時に必要です' required>
      <button type='submit' class='btn-submit'>🚀 投稿する</button>
    </form>"
  html + sidebar_content
end

get '/post/:id' do
  post = nil
  query { |db| post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first }
  redirect '/' unless post
  
  html = header_menu + "
    <div style='background:white; padding:30px; border-radius:12px;'>
      <h1>#{post[7]}</h1>
      <p>💊 #{post[2]} | 👨‍⚕️ #{post[1]} | 📅 #{post[6]}</p>
      <hr><div style='line-height:1.8;'>#{post[4].gsub("\n", "<br>")}</div><hr>
      
      <div style='margin-top:30px; padding:20px; background:#fff5f5; border-radius:8px;'>
        <h4 style='margin-top:0; color:#d9534f;'>🗑️ この投稿を削除する</h4>
        <form action='/post_delete/#{post[0]}' method='post' style='display:flex; gap:10px;'>
          <input type='password' name='del_pass' placeholder='パスワードを入力' style='margin:0; flex:1;'>
          <button type='submit' class='btn-delete'>削除実行</button>
        </form>
      </div>
    </div>"
  html + sidebar_content
end

# --- アクション ---

post '/post' do
  query do |db|
    db.execute("INSERT INTO posts (user_name, drug_name, message, parent_id, title, created_at, password) VALUES (?, ?, ?, ?, ?, ?, ?)", 
               [params[:user_name], params[:drug_name], params[:message], -1, params[:title], Time.now.strftime('%Y-%m-%d %H:%M'), params[:password]])
  end
  redirect '/'
end

post '/post_delete/:id' do
  query do |db|
    # まずパスワードをチェック
    post = db.execute("SELECT password FROM posts WHERE id = ?", [params[:id]]).first
    if post && post[0] == params[:del_pass]
      db.execute("DELETE FROM posts WHERE id = ?", [params[:id]])
      redirect '/'
    else
      "パスワードが違います。<a href='/post/#{params[:id]}'>戻る</a>"
    end
  end
end