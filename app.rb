require 'sinatra'
require 'sqlite3'
require 'time'
require 'fileutils'

set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
enable :sessions
set :session_secret, 'pharmacist_secret_key_katabami_papa_mama_children_2026_super_long_secret_key_64_bytes'

# --- データベース準備 ---
def setup_db
  db = SQLite3::Database.new "sns_v4.db" # 検索機能のために少し構造を整理
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
      password TEXT,
      image_path TEXT
    );
  SQL
  db.close
end
setup_db

def query
  db = SQLite3::Database.new "sns_v4.db"
  yield db
ensure
  db.close if db
end

# --- デザイン（CSS追加：フラッシュメッセージ用） ---
def header_menu
  user_status = if session[:user]
    "<span class='user-badge'>👤 #{session[:user]}</span> <a href='/logout' class='nav-link logout'>ログアウト</a>"
  else
    "<a href='/login_page' class='nav-link login'>ログイン</a>"
  end

  # 通知メッセージ（フラッシュメッセージ）の取得
  flash_msg = ""
  if session[:notice]
    flash_msg = "<div class='flash-notice'>#{session[:notice]}</div>"
    session[:notice] = nil # 一度表示したら消す
  end

  "
  <style>
    :root { --primary: #0071e3; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --secondary: #86868b; }
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background-color: var(--bg); color: var(--text); }
    .container { max-width: 700px; margin: 0 auto; padding: 40px 20px; }
    nav { background: rgba(255, 255, 255, 0.8); backdrop-filter: blur(20px); padding: 12px 20px; display: flex; justify-content: space-between; align-items: center; position: sticky; top: 0; z-index: 100; border-bottom: 1px solid rgba(0,0,0,0.1); }
    .nav-brand { font-weight: 700; font-size: 1.2rem; color: var(--primary); text-decoration: none; }
    .nav-links a { color: var(--text); text-decoration: none; font-weight: 500; margin-left: 20px; font-size: 0.9rem; }
    .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 24px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); border: 1px solid rgba(0,0,0,0.03); }
    .drug-tag { display: inline-block; background: #e8f2ff; color: var(--primary); padding: 4px 10px; border-radius: 6px; font-size: 0.8rem; font-weight: 600; margin-bottom: 12px; }
    .btn-action { background: #f5f5f7; border: none; padding: 8px 16px; border-radius: 980px; cursor: pointer; color: var(--text); font-weight: 600; font-size: 0.85rem; text-decoration: none; }
    .btn-submit { background: var(--primary); color: white; border: none; padding: 12px 24px; border-radius: 980px; cursor: pointer; font-weight: 600; width: 100%; font-size: 1rem; }
    input, textarea { width: 100%; padding: 14px; margin: 10px 0; border: 1px solid #d2d2d7; border-radius: 12px; box-sizing: border-box; }
    
    /* 検索窓のデザイン */
    .search-box { margin-bottom: 30px; display: flex; gap: 10px; }
    .search-input { margin: 0; flex: 1; }

    /* フラッシュメッセージ */
    .flash-notice { background: #32d74b; color: white; padding: 15px; text-align: center; font-weight: 600; position: fixed; top: 60px; left: 0; right: 0; z-index: 99; animation: slideDown 0.5s ease; }
    @keyframes slideDown { from { transform: translateY(-100%); } to { transform: translateY(0); } }
  </style>
  <nav>
    <a href='/' class='nav-brand'>PharmaShare</a>
    <div class='nav-links'>
      <a href='/'>🏠 ホーム</a>
      <a href='/post_new'>✍️ 投稿</a>
      #{user_status}
    </div>
  </nav>
  #{flash_msg}
  <div class='container'>
  "
end

# --- ルート ---

get '/' do
  search_word = params[:q]
  html = header_menu
  html += "
    <h1 style='font-size: 2rem; margin-bottom: 10px;'>最新の知恵</h1>
    <form action='/' method='get' class='search-box'>
      <input type='text' name='q' class='search-input' placeholder='薬品名で検索（例：アドエア）' value='#{search_word}'>
      <button type='submit' class='btn-action' style='background:var(--primary); color:white;'>検索</button>
    </form>
  "

  query do |db|
    sql = "SELECT * FROM posts WHERE parent_id = -1"
    args = []
    if search_word && search_word != ""
      sql += " AND drug_name LIKE ?"
      args << "%#{search_word}%"
    end
    sql += " ORDER BY id DESC"

    db.execute(sql, args).each do |row|
      html += "
      <div class='post-card'>
        <div style='font-size: 0.8rem; color:var(--secondary);'>👨‍⚕️ #{row[1]} | 📅 #{row[6]}</div>
        <span class='drug-tag'>💊 #{row[2]}</span>
        <a href='/post/#{row[0]}' style='font-size:1.4rem; font-weight:700; text-decoration:none; color:var(--text); display:block; margin:8px 0;'>#{row[7]}</a>
        #{ row[9] ? "<img src='/uploads/#{row[9]}' style='width:100%; border-radius:12px; margin-top:16px;'>" : "" }
        <div style='margin-top:20px; display:flex; gap:12px;'>
          <form action='/like/#{row[0]}' method='post'><button type='submit' class='btn-action'>❤️ #{row[3]}</button></form>
          <a href='/post/#{row[0]}' class='btn-action'>💬 返信・詳細</a>
        </div>
      </div>"
    end
  end
  html + "</div>"
end

get '/post_new' do
  return header_menu + "<div class='post-card'><h2>ログインが必要です</h2><a href='/login_page' class='btn-submit' style='text-decoration:none; display:block; text-align:center;'>ログインへ</a></div></div>" unless session[:user]
  header_menu + "
    <div class='post-card'>
      <h2>✍️ 知恵を共有する</h2>
      <form action='/post' method='post' enctype='multipart/form-data'>
        <input type='hidden' name='user_name' value='#{session[:user]}'>
        <label>タイトル</label><input type='text' name='title' required>
        <label>対象の薬品名</label><input type='text' name='drug_name' required>
        <label>内容</label><textarea name='message' style='height:120px;' required></textarea>
        <label>📸 写真</label><input type='file' name='myfile' accept='image/*'>
        <label>🔑 削除用パスワード</label><input type='password' name='password' required>
        <button type='submit' class='btn-submit'>🚀 投稿を公開する</button>
      </form>
    </div></div>"
end

get '/post/:id' do
  post, replies = nil, []
  query do |db|
    post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first
    replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [params[:id]])
  end
  redirect '/' unless post
  
  html = header_menu + "
    <a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
    <div class='post-card' style='margin-top:20px;'>
      <div style='font-size:0.8rem; color:var(--secondary);'>👨‍⚕️ #{post[1]} | 📅 #{post[6]}</div>
      <span class='drug-tag'>💊 #{post[2]}</span>
      <h1 style='margin:10px 0;'>#{post[7]}</h1>
      #{ post[9] ? "<img src='/uploads/#{post[9]}' style='width:100%; border-radius:12px;'>" : "" }
      <div style='margin:24px 0; line-height:1.8; white-space: pre-wrap;'>#{post[4]}</div>
      <hr style='border:0; border-top:1px solid #eee;'>
      <form action='/post_delete/#{post[0]}' method='post' style='display:flex; gap:10px;'>
        <input type='password' name='del_pass' placeholder='削除パスワード' style='margin:0; flex:1;'>
        <button type='submit' style='background:#ff3b30; color:white; border:none; padding:10px 20px; border-radius:12px; cursor:pointer;'>🗑️ 削除</button>
      </form>
    </div>"
    # (返信表示とフォーム部分は前と同じなので省略せず実装...)
  replies.each { |r| html += "<div class='post-card' style='margin-left:20px; background:#fbfbfd;'><div>👨‍⚕️ #{r[1]}</div><p>#{r[4]}</p></div>" }
  if session[:user]
    html += "<div class='post-card'><h4>返信</h4><form action='/post' method='post'><input type='hidden' name='parent_id' value='#{post[0]}'><input type='hidden' name='user_name' value='#{session[:user]}'><input type='hidden' name='title' value='Re: #{post[7]}'><input type='hidden' name='drug_name' value='#{post[2]}'><textarea name='message' required></textarea><input type='password' name='password' required><button type='submit' class='btn-submit'>返信を送る</button></form></div>"
  end
  html + "</div>"
end

# --- アクション ---

post '/login' do
  session[:user] = params[:user_name]
  session[:notice] = "ようこそ、#{session[:user]} さん！"
  redirect '/'
end

get '/logout' do
  session.clear
  session[:notice] = "ログアウトしました"
  redirect '/'
end

post '/post' do
  img_name = nil
  if params[:myfile]
    img_name = Time.now.to_i.to_s + "_" + params[:myfile][:filename]
    FileUtils.cp(params[:myfile][:tempfile].path, "./public/uploads/#{img_name}")
  end
  parent_id = params[:parent_id] || -1
  # 日本時間(JST)で時間を取得
  jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')

  query do |db|
    db.execute("INSERT INTO posts (user_name, drug_name, message, title, created_at, password, image_path, parent_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
               [params[:user_name], params[:drug_name], params[:message], params[:title], jst_time, params[:password], img_name, parent_id])
  end
  session[:notice] = parent_id == -1 ? "新しい知恵を投稿しました！" : "返信を送信しました！"
  redirect (parent_id == -1 ? '/' : "/post/#{parent_id}")
end

post '/post_delete/:id' do
  query do |db|
    post = db.execute("SELECT password FROM posts WHERE id = ?", [params[:id]]).first
    if post && post[0] == params[:del_pass]
      db.execute("DELETE FROM posts WHERE id = ?", [params[:id]])
      session[:notice] = "投稿を削除しました"
      redirect '/'
    else
      session[:notice] = "パスワードが正しくありません"
      redirect "/post/#{params[:id]}"
    end
  end
end

post '/like/:id' do
  query { |db| db.execute("UPDATE posts SET likes = likes + 1 WHERE id = ?", [params[:id]]) }
  redirect '/' # いいねは通知なしでサクサク動かす
end

get '/login_page' do
  header_menu + "<div class='post-card'><h2>🔑 ログイン</h2><form action='/login' method='post'><input type='text' name='user_name' placeholder='名前' required><button type='submit' class='btn-submit'>ログイン</button></form></div></div>"
end

get '/uploads/:filename' do
  send_file "./public/uploads/#{params[:filename]}"
end