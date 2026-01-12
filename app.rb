require 'sinatra'
require 'sqlite3'
require 'time'
require 'fileutils'

set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
enable :sessions
set :session_secret, 'pharmacist_secret_key_katabami_papa_mama_children_2026_super_long_secret_key_64_bytes'
ENV['TZ'] = 'Asia/Tokyo'

# --- データベース準備 ---
def setup_db
  db = SQLite3::Database.new "sns_v3.db"
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
  db = SQLite3::Database.new "sns_v3.db"
  yield db
ensure
  db.close if db
end

# --- デザイン（CSSを大幅に強化！） ---
def header_menu
  user_status = if session[:user]
    "<span class='user-badge'>👤 #{session[:user]}</span> <a href='/logout' class='nav-link logout'>ログアウト</a>"
  else
    "<a href='/login_page' class='nav-link login'>ログイン</a>"
  end

  "
  <style>
    :root {
      --primary: #0071e3; /* Apple風のブルー */
      --bg: #f5f5f7;
      --card: #ffffff;
      --text: #1d1d1f;
      --secondary: #86868b;
    }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; margin: 0; background-color: var(--bg); color: var(--text); line-height: 1.5; }
    .container { max-width: 700px; margin: 0 auto; padding: 40px 20px; }
    
    /* ナビゲーション */
    nav { background: rgba(255, 255, 255, 0.8); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); padding: 12px 20px; display: flex; justify-content: space-between; align-items: center; position: sticky; top: 0; z-index: 100; border-bottom: 1px solid rgba(0,0,0,0.1); }
    .nav-brand { font-weight: 700; font-size: 1.2rem; color: var(--primary); text-decoration: none; }
    .nav-links a { color: var(--text); text-decoration: none; font-weight: 500; margin-left: 20px; font-size: 0.9rem; transition: 0.2s; }
    .nav-links a:hover { color: var(--primary); }
    
    /* カードデザイン */
    .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 24px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); transition: transform 0.3s ease; border: 1px solid rgba(0,0,0,0.03); }
    .post-card:hover { transform: translateY(-2px); box-shadow: 0 8px 24px rgba(0,0,0,0.1); }
    
    /* タイポグラフィ */
    .post-meta { font-size: 0.8rem; color: var(--secondary); margin-bottom: 8px; }
    .post-title { font-size: 1.4rem; font-weight: 700; margin: 8px 0; color: var(--text); text-decoration: none; display: block; }
    .drug-tag { display: inline-block; background: #e8f2ff; color: var(--primary); padding: 4px 10px; border-radius: 6px; font-size: 0.8rem; font-weight: 600; margin-bottom: 12px; }
    
    /* 画像とボタン */
    .post-img { width: 100%; border-radius: 12px; margin-top: 16px; object-fit: cover; max-height: 400px; }
    .btn-action { background: #f5f5f7; border: none; padding: 8px 16px; border-radius: 980px; cursor: pointer; color: var(--text); font-weight: 600; font-size: 0.85rem; transition: 0.2s; text-decoration: none; display: inline-block; }
    .btn-action:hover { background: #e8e8ed; }
    .btn-like.active { color: #ff3b30; }
    .btn-submit { background: var(--primary); color: white; border: none; padding: 12px 24px; border-radius: 980px; cursor: pointer; font-weight: 600; width: 100%; font-size: 1rem; }

    /* フォーム */
    input, textarea { width: 100%; padding: 14px; margin: 10px 0; border: 1px solid #d2d2d7; border-radius: 12px; box-sizing: border-box; font-size: 1rem; background: #fbfbfd; }
    input:focus { outline: none; border-color: var(--primary); }
    label { font-size: 0.85rem; font-weight: 600; color: var(--secondary); }
  </style>
  <nav>
    <a href='/' class='nav-brand'>PharmaShare</a>
    <div class='nav-links'>
      <a href='/'>🏠 ホーム</a>
      <a href='/post_new'>✍️ 投稿</a>
      #{user_status}
    </div>
  </nav>
  <div class='container'>
  "
end

# --- ルート ---

get '/' do
  html = header_menu + "<h1 style='font-size: 2rem; margin-bottom: 30px;'>最新の知恵</h1>"
  query do |db|
    db.execute("SELECT * FROM posts WHERE parent_id = -1 ORDER BY id DESC").each do |row|
      html += "
      <div class='post-card'>
        <div class='post-meta'>👨‍⚕️ #{row[1]} | 📅 #{row[6]}</div>
        <span class='drug-tag'>💊 #{row[2]}</span>
        <a href='/post/#{row[0]}' class='post-title'>#{row[7]}</a>
        #{ row[9] ? "<img src='/uploads/#{row[9]}' class='post-img'>" : "" }
        <div style='margin-top:20px; display:flex; gap:12px;'>
          <form action='/like/#{row[0]}' method='post' style='margin:0;'>
            <button type='submit' class='btn-action'>❤️ #{row[3]}</button>
          </form>
          <a href='/post/#{row[0]}' class='btn-action'>💬 返信・詳細</a>
        </div>
      </div>"
    end
  end
  html + "</div>"
end

get '/post_new' do
  unless session[:user]
    return header_menu + "<div class='post-card'><h2>ログインが必要です</h2><p>投稿するには名前を教えてください。</p><a href='/login_page' class='btn-submit' style='text-decoration:none; display:block; text-align:center;'>ログイン画面へ</a></div></div>"
  end

  html = header_menu + "
  <div class='post-card'>
    <h2 style='margin-top:0;'>✍️ 知恵を共有する</h2>
    <form action='/post' method='post' enctype='multipart/form-data'>
      <input type='hidden' name='user_name' value='#{session[:user]}'>
      <label>タイトル</label><input type='text' name='title' placeholder='例：吸入指導のコツ' required>
      <label>対象の薬品名</label><input type='text' name='drug_name' placeholder='例：アドエア' required>
      <label>内容</label><textarea name='message' style='height:120px;' placeholder='具体的な事例や気づきを記入してください' required></textarea>
      <label>📸 写真（任意）</label><input type='file' name='myfile' accept='image/*'>
      <label>🔑 削除用パスワード</label><input type='password' name='password' required>
      <button type='submit' class='btn-submit'>🚀 投稿を公開する</button>
    </form>
  </div>"
  html + "</div>"
end

get '/post/:id' do
  post = nil
  replies = []
  query do |db|
    post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first
    replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [params[:id]])
  end
  redirect '/' unless post
  
  html = header_menu + "
    <a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
    <div class='post-card' style='margin-top:20px;'>
      <div class='post-meta'>👨‍⚕️ #{post[1]} | 📅 #{post[6]}</div>
      <span class='drug-tag'>💊 #{post[2]}</span>
      <h1 style='margin:10px 0;'>#{post[7]}</h1>
      #{ post[9] ? "<img src='/uploads/#{post[9]}' class='post-img'>" : "" }
      <div style='margin:24px 0; font-size:1.1rem; line-height:1.8; white-space: pre-wrap;'>#{post[4]}</div>
    </div>
    
    <h3 style='margin:40px 0 20px;'>💬 返信 (#{replies.size})</h3>"
    
  replies.each do |r|
    html += "
    <div class='post-card' style='padding:16px; margin-left:20px; background:#fbfbfd;'>
      <div class='post-meta'>👨‍⚕️ #{r[1]} | 📅 #{r[6]}</div>
      <div style='margin-top:8px;'>#{r[4]}</div>
    </div>"
  end

  if session[:user]
    html += "
    <div class='post-card' style='margin-top:40px; border: 2px solid #e8f2ff;'>
      <h4 style='margin-top:0;'>返信を投稿する</h4>
      <form action='/post' method='post'>
        <input type='hidden' name='parent_id' value='#{post[0]}'>
        <input type='hidden' name='user_name' value='#{session[:user]}'>
        <input type='hidden' name='title' value='Re: #{post[7]}'>
        <input type='hidden' name='drug_name' value='#{post[2]}'>
        <textarea name='message' placeholder='コメントを入力' required style='height:80px;'></textarea>
        <input type='password' name='password' placeholder='削除用パスワード' required>
        <button type='submit' class='btn-submit'>返信を送る</button>
      </form>
    </div>"
  end
  html + "</div>"
end

# --- アクション ---

get '/login_page' do
  header_menu + "
    <div class='post-card' style='max-width:400px; margin: 40px auto;'>
      <h2 style='text-align:center;'>🔑 ログイン</h2>
      <form action='/login' method='post'>
        <input type='text' name='user_name' placeholder='お名前' required>
        <button type='submit' class='btn-submit'>ログイン</button>
      </form>
    </div></div>"
end

post '/login' do
  session[:user] = params[:user_name]
  redirect '/'
end

get '/logout' do
  session.clear
  redirect '/'
end

post '/post' do
  img_name = nil
  if params[:myfile]
    img_name = Time.now.to_i.to_s + "_" + params[:myfile][:filename]
    FileUtils.cp(params[:myfile][:tempfile].path, "./public/uploads/#{img_name}")
  end
  parent_id = params[:parent_id] || -1
  query do |db|
    db.execute("INSERT INTO posts (user_name, drug_name, message, title, created_at, password, image_path, parent_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
               [params[:user_name], params[:drug_name], params[:message], params[:title], Time.now.strftime('%m/%d %H:%M'), params[:password], img_name, parent_id])
  end
  redirect (parent_id == -1 ? '/' : "/post/#{parent_id}")
end

post '/like/:id' do
  query { |db| db.execute("UPDATE posts SET likes = likes + 1 WHERE id = ?", [params[:id]]) }
  redirect '/'
end

get '/uploads/:filename' do
  send_file "./public/uploads/#{params[:filename]}"
end