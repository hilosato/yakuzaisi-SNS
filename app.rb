require 'sinatra'
require 'sqlite3'
require 'time'
require 'bcrypt'

# --- サーバー設定 ---
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

# セッションを強固に固定（これで再起動してもログインやメアド状態が消えにくくなるよ）
use Rack::Session::Cookie, :key => 'rack.session',
                           :path => '/',
                           :secret => 'katabami_pharmashare_2026_fixed_secret_key'

DB_NAME = "sns.db"

# カテゴリ定義
CATEGORIES = {
  "指導のコツ" => "#0071e3", # 青
  "症例報告" => "#32d74b",   # 緑
  "新薬情報" => "#ff9f0a",   # オレンジ
  "その他" => "#86868b"      # グレー
}

def setup_db
  db = SQLite3::Database.new DB_NAME
  db.execute "CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT, drug_name TEXT, likes INTEGER DEFAULT 0, message TEXT, parent_id INTEGER DEFAULT -1, created_at TEXT, title TEXT, image_path TEXT, category TEXT);"
  db.execute "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT UNIQUE, password_digest TEXT, email TEXT);"
  db.close
end
setup_db

def query
  db = SQLite3::Database.new DB_NAME
  yield db
ensure
  db.close if db
end

# --- デザイン（Apple風スタイル） ---
def header_menu
  user_status = if session[:user]
    "<a href='/post_new' class='nav-link'>✍️ 投稿</a> 
     <a href='/profile' class='nav-link'>👤 設定</a> 
     <a href='/logout' class='nav-link'>ログアウト</a>"
  else
    "<a href='/login_page' class='nav-link'>ログイン / 登録</a>"
  end

  flash_msg = session[:notice] ? "<div class='flash-notice'>#{session[:notice]}</div>" : ""
  session[:notice] = nil

  "
  <style>
    :root { --primary: #0071e3; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --secondary: #86868b; --accent: #32d74b; }
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; background: var(--bg); color: var(--text); line-height: 1.5; }
    .container { max-width: 700px; margin: 0 auto; padding: 40px 20px; }
    nav { background: rgba(255, 255, 255, 0.8); backdrop-filter: blur(20px); padding: 12px 20px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0,0,0,0.1); position: sticky; top: 0; z-index: 100; }
    .nav-brand { font-weight: 700; color: var(--primary); text-decoration: none; font-size: 1.2rem; }
    .nav-link { color: var(--text); text-decoration: none; font-size: 0.9rem; margin-left: 15px; font-weight: 500; }
    .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .btn-primary { background: var(--primary); color: white; border: none; padding: 12px 24px; border-radius: 980px; cursor: pointer; font-weight: 600; width: 100%; text-decoration: none; display: block; text-align: center; box-sizing: border-box; }
    .flash-notice { background: var(--accent); color: white; padding: 15px; text-align: center; font-weight: 600; }
    .lock-banner { background: #fff9e6; border: 1px solid #ffe58f; padding: 20px; border-radius: 12px; text-align: center; margin-bottom: 20px; }
    .tag { padding: 4px 10px; border-radius: 6px; font-size: 0.75rem; font-weight: 700; color: white; margin-right: 8px; vertical-align: middle; }
    input, textarea, select { width: 100%; padding: 14px; margin: 8px 0; border: 1px solid #d2d2d7; border-radius: 12px; box-sizing: border-box; font-size: 1rem; background: white; }
    .search-box { margin-bottom: 30px; display: flex; gap: 10px; }
    .search-box input { margin: 0; }
    .search-box button { width: 100px; border-radius: 12px; background: var(--secondary); color: white; border: none; cursor: pointer; font-weight: 600; }
  </style>
  <nav>
    <a href='/' class='nav-brand'>PharmaShare</a>
    <div class='nav-links'><a href='/' class='nav-link'>🏠 ホーム</a>#{user_status}</div>
  </nav>
  #{flash_msg}
  <div class='container'>
  "
end

# --- メインロジック ---

get '/' do
  word = params[:search]
  html = header_menu + "<h1>最新の知恵</h1>"
  html += "<form action='/' method='get' class='search-box'><input type='text' name='search' placeholder='薬品名やキーワード検索...' value='#{word}'><button type='submit'>検索</button></form>"

  query do |db|
    sql = "SELECT * FROM posts WHERE (parent_id = -1 OR parent_id = '-1')"
    sql_params = []
    if word && word != ""
      sql += " AND (title LIKE ? OR drug_name LIKE ? OR message LIKE ?)"
      sql_params += ["%#{word}%", "%#{word}%", "%#{word}%"]
    end
    sql += " ORDER BY id DESC"
    posts = db.execute(sql, sql_params)
    
    if posts.empty?
      html += "<p style='color:var(--secondary);'>投稿が見つかりませんでした。</p>"
    else
      posts.each do |row|
        cat_name = row[9] || "その他"
        cat_color = CATEGORIES[cat_name] || "#86868b"
        html += "<div class='post-card'><span class='tag' style='background:#{cat_color};'>#{cat_name}</span><span style='color:var(--secondary); font-size:0.8rem;'>💊 #{row[2]}</span><h2 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:var(--text);'>#{row[7]}</a></h2><p style='color:var(--secondary); font-size:0.85rem;'>👨‍⚕️ #{row[1]} | 📅 #{row[6]}</p><a href='/post/#{row[0]}' style='color:var(--primary); font-weight:600; text-decoration:none;'>詳細をよむ →</a></div>"
      end
    end
  end
  html + "</div>"
end

get '/post/:id' do
  unless session[:user]
    return header_menu + "<div class='lock-banner'><h3>🔒 続きはログイン後に読めます</h3><a href='/login_page' class='btn-primary'>ログイン / 登録</a></div></div>"
  end

  post, replies, user_email = nil, [], nil
  query do |db|
    post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first
    replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [params[:id]])
    user_email = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first&.at(0)
  end
  redirect '/' unless post

  cat_name = post[9] || "その他"
  cat_color = CATEGORIES[cat_name] || "#86868b"

  html = header_menu + "
    <a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
    <div class='post-card' style='margin-top:20px;'>
      <span class='tag' style='background:#{cat_color};'>#{cat_name}</span>
      <span style='color:var(--secondary); font-size:0.8rem;'>💊 #{post[2]}</span>
      <h1>#{post[7]}</h1>
      <p style='color:var(--secondary); font-size:0.85rem;'>投稿者: #{post[1]} | 日時: #{post[6]}</p>
      <div style='line-height:1.8; white-space: pre-wrap; margin:20px 0; font-size:1.1rem;'>#{post[4]}</div>
    </div>"

  html += "<h3>💬 返信 (#{replies.size})</h3>"
  replies.each { |r| html += "<div class='post-card' style='margin-left:20px; background:#fbfbfd;'><div>👨‍⚕️ #{r[1]}</div><p>#{r[4]}</p></div>" }

  if user_email && user_email != ""
    html += "<div class='post-card'><h4>返信を書く</h4><form action='/post' method='post'><input type='hidden' name='parent_id' value='#{post[0]}'><input type='hidden' name='category' value='#{cat_name}'><input type='hidden' name='drug_name' value='#{post[2]}'><input type='hidden' name='title' value='Re: #{post[7]}'><textarea name='message' required></textarea><button type='submit' class='btn-primary'>返信を送る</button></form></div>"
  else
    html += "<div class='lock-banner'><h4>✉️ 返信にはメアド登録が必要です</h4><a href='/profile' class='btn-primary'>設定画面で登録</a></div>"
  end
  html + "</div>"
end

get '/post_new' do
  redirect '/login_page' unless session[:user]
  user_email = nil
  query { |db| user_email = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first&.at(0) }

  if user_email.nil? || user_email == ""
    session[:notice] = "投稿にはメールアドレスの登録が必要です"
    redirect '/profile'
  end

  cat_options = CATEGORIES.keys.map { |c| "<option value='#{c}'>#{c}</option>" }.join
  header_menu + "<div class='post-card'><h2>✍️ 知恵を共有する</h2><form action='/post' method='post'><input type='hidden' name='parent_id' value='-1'><label>カテゴリ</label><select name='category'>#{cat_options}</select><label>タイトル</label><input type='text' name='title' required><label>薬品名</label><input type='text' name='drug_name' required><label>内容</label><textarea name='message' style='height:200px;' required></textarea><button type='submit' class='btn-primary'>公開する</button></form></div></div>"
end

get '/profile' do
  redirect '/login_page' unless session[:user]
  user_email = nil
  query { |db| user_email = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first&.at(0) }
  
  header_menu + "<div class='post-card'><h2>👤 設定</h2><p>ユーザー名: <strong>#{session[:user]}</strong></p><form action='/update_profile' method='post'><label>メールアドレス</label><input type='email' name='email' value='#{user_email}' required placeholder='example@mail.com'><button type='submit' class='btn-primary' style='background:var(--accent);'>保存して投稿を有効にする</button></form></div></div>"
end

post '/update_profile' do
  redirect '/login_page' unless session[:user]
  query { |db| db.execute("UPDATE users SET email = ? WHERE user_name = ?", [params[:email], session[:user]]) }
  session[:notice] = "メアドを登録しました！そのまま投稿できます。"
  redirect '/post_new'
end

post '/auth' do
  user_name, password = params[:user_name], params[:password]
  query do |db|
    user = db.execute("SELECT * FROM users WHERE user_name = ?", [user_name]).first
    if user
      if BCrypt::Password.new(user[2]) == password
        session[:user] = user_name
        session[:notice] = "おかえりなさい！"
        redirect '/'
      else
        session[:notice] = "パスワードが違います"
        redirect '/login_page'
      end
    else
      hash_pass = BCrypt::Password.create(password)
      db.execute("INSERT INTO users (user_name, password_digest) VALUES (?, ?)", [user_name, hash_pass])
      session[:user] = user_name
      session[:notice] = "登録完了しました！"
      redirect '/'
    end
  end
end

get '/login_page' do
  header_menu + "<div class='post-card' style='max-width:400px; margin: 0 auto;'><h2 style='text-align:center;'>🔑 ログイン / 登録</h2><form action='/auth' method='post'><input type='text' name='user_name' placeholder='名前' required><input type='password' name='password' placeholder='パスワード' required><button type='submit' class='btn-primary'>ログイン・登録</button></form></div></div>"
end

post '/post' do
  redirect '/login_page' unless session[:user]
  jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')
  p_id = params[:parent_id].to_i
  query do |db|
    db.execute("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id, category) VALUES (?, ?, ?, ?, ?, ?, ?)", 
               [session[:user], params[:drug_name], params[:message], params[:title], jst_time, p_id, params[:category]])
  end
  session[:notice] = "投稿完了！"
  redirect (p_id == -1 ? '/' : "/post/#{p_id}")
end

get '/logout' do
  session.clear
  session[:notice] = "ログアウトしました"
  redirect '/'
end