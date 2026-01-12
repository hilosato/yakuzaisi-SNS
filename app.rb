require 'sinatra'
require 'sqlite3'
require 'time'
require 'bcrypt'

# ポートとセッションの設定
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
enable :sessions

# セキュリティキーを固定（これで再起動してもログインが切れにくくなるよ）
set :session_secret, 'katabami_pharmashare_2026_long_secret_key_for_stability_check_64bytes_minimum'

# --- データベース準備 ---
# ファイル名を「sns.db」に固定するね
DB_NAME = "sns.db"

def setup_db
  db = SQLite3::Database.new DB_NAME
  # 投稿テーブル
  db.execute "CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT, drug_name TEXT, likes INTEGER DEFAULT 0, message TEXT, parent_id INTEGER DEFAULT -1, created_at TEXT, title TEXT, image_path TEXT);"
  # ユーザーテーブル
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

# --- デザイン ---
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
    body { font-family: -apple-system, sans-serif; margin: 0; background: var(--bg); color: var(--text); line-height: 1.5; }
    .container { max-width: 700px; margin: 0 auto; padding: 40px 20px; }
    nav { background: rgba(255, 255, 255, 0.8); backdrop-filter: blur(20px); padding: 12px 20px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0,0,0,0.1); position: sticky; top: 0; z-index: 100; }
    .nav-brand { font-weight: 700; color: var(--primary); text-decoration: none; font-size: 1.2rem; }
    .nav-link { color: var(--text); text-decoration: none; font-size: 0.9rem; margin-left: 15px; font-weight: 500; }
    .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); border: 1px solid rgba(0,0,0,0.02); }
    .btn-primary { background: var(--primary); color: white; border: none; padding: 12px 24px; border-radius: 980px; cursor: pointer; font-weight: 600; width: 100%; text-decoration: none; display: block; text-align: center; box-sizing: border-box; }
    .flash-notice { background: var(--accent); color: white; padding: 15px; text-align: center; font-weight: 600; border-radius: 0 0 12px 12px; }
    .lock-banner { background: #fff9e6; border: 1px solid #ffe58f; padding: 20px; border-radius: 12px; text-align: center; margin-bottom: 20px; }
    .tag { background: #e8f2ff; color: var(--primary); padding: 4px 8px; border-radius: 6px; font-size: 0.8rem; font-weight: 600; }
    input, textarea { width: 100%; padding: 14px; margin: 8px 0; border: 1px solid #d2d2d7; border-radius: 12px; box-sizing: border-box; font-size: 1rem; }
  </style>
  <nav>
    <a href='/' class='nav-brand'>PharmaShare</a>
    <div class='nav-links'><a href='/' class='nav-link'>🏠 ホーム</a>#{user_status}</div>
  </nav>
  #{flash_msg}
  <div class='container'>
  "
end

# --- ページ一覧 ---

get '/' do
  html = header_menu + "<h1>最新の知恵</h1>"
  
  query do |db|
    # parent_id = -1 のものが「元の投稿」だよ
    posts = db.execute("SELECT * FROM posts WHERE parent_id = -1 OR parent_id = '-1' ORDER BY id DESC")
    
    if posts.empty?
      html += "<p style='color:var(--secondary);'>まだ投稿がありません。最初の知恵を投稿してみませんか？</p>"
    else
      posts.each do |row|
        html += "
        <div class='post-card'>
          <span class='tag'>💊 #{row[2]}</span>
          <h2 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:var(--text);'>#{row[7]}</a></h2>
          <p style='color:var(--secondary); font-size:0.85rem;'>👨‍⚕️ #{row[1]} | 📅 #{row[6]}</p>
          <a href='/post/#{row[0]}' style='color:var(--primary); font-weight:600; text-decoration:none;'>詳細をよむ →</a>
        </div>"
      end
    end
  end
  html + "</div>"
end

get '/post/:id' do
  unless session[:user]
    return header_menu + "<div class='lock-banner'><h3>🔒 続きはログイン後に読めます</h3><p>詳細を読むにはアカウント作成（メアド不要）が必要です。</p><a href='/login_page' class='btn-primary'>ログイン / 登録して続きを読む</a></div></div>"
  end

  post, replies, user_email = nil, [], nil
  query do |db|
    post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first
    replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [params[:id]])
    user_email = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first&.at(0)
  end
  
  redirect '/' unless post

  html = header_menu + "
    <a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
    <div class='post-card' style='margin-top:20px;'>
      <span class='tag'>💊 #{post[2]}</span>
      <h1>#{post[7]}</h1>
      <p style='color:var(--secondary); font-size:0.85rem;'>投稿者: #{post[1]} | 日時: #{post[6]}</p>
      <div style='line-height:1.8; white-space: pre-wrap; margin:20px 0; font-size:1.1rem;'>#{post[4]}</div>
    </div>"

  html += "<h3 style='margin-top:40px;'>💬 返信 (#{replies.size})</h3>"
  replies.each do |r| 
    html += "<div class='post-card' style='margin-left:20px; background:#fbfbfd;'>
               <div style='font-weight:600; font-size:0.9rem;'>👨‍⚕️ #{r[1]}</div>
               <div style='margin-top:10px;'>#{r[4]}</div>
             </div>" 
  end

  if user_email && user_email != ""
    html += "
      <div class='post-card'>
        <h4>返信を書く</h4>
        <form action='/post' method='post'>
          <input type='hidden' name='parent_id' value='#{post[0]}'>
          <input type='hidden' name='drug_name' value='#{post[2]}'>
          <input type='hidden' name='title' value='Re: #{post[7]}'>
          <textarea name='message' required placeholder='コメントを入力'></textarea>
          <button type='submit' class='btn-primary'>返信を送る</button>
        </form>
      </div>"
  else
    html += "<div class='lock-banner'><h4>✉️ 返信にはメアド登録が必要です</h4><a href='/profile' class='btn-primary' style='background:#17a2b8;'>設定画面でメアドを登録する</a></div>"
  end
  html + "</div>"
end

get '/post_new' do
  redirect '/login_page' unless session[:user]
  user_email = nil
  query { |db| user_email = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first&.at(0) }

  if user_email && user_email != ""
    header_menu + "
      <div class='post-card'>
        <h2>✍️ 知恵を共有する</h2>
        <form action='/post' method='post'>
          <input type='hidden' name='parent_id' value='-1'>
          <label>タイトル</label><input type='text' name='title' required placeholder='例：吸入指導のコツ'>
          <label>薬品名</label><input type='text' name='drug_name' required placeholder='例：アドエア'>
          <label>内容</label><textarea name='message' style='height:200px;' required placeholder='内容を詳しく入力してください'></textarea>
          <button type='submit' class='btn-primary'>世界中の薬剤師に公開する</button>
        </form>
      </div></div>"
  else
    header_menu + "<div class='lock-banner'><h3>✉️ 投稿にはメールアドレスの登録が必要です</h3><p>信頼性向上のため、発信者にはメールアドレスの登録をお願いしています。</p><a href='/profile' class='btn-primary'>設定画面でメアドを登録する</a></div></div>"
  end
end

get '/profile' do
  redirect '/login_page' unless session[:user]
  user_email = nil
  query { |db| user_email = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first&.at(0) }
  
  header_menu + "
    <div class='post-card'>
      <h2>👤 設定</h2>
      <p>ユーザー名: <strong>#{session[:user]}</strong></p>
      <form action='/update_profile' method='post'>
        <label>メールアドレス (投稿・コメントに必要)</label>
        <input type='email' name='email' value='#{user_email}' placeholder='example@mail.com' required>
        <button type='submit' class='btn-primary' style='background:var(--accent);'>保存して投稿を有効にする</button>
      </form>
    </div></div>"
end

post '/update_profile' do
  query { |db| db.execute("UPDATE users SET email = ? WHERE user_name = ?", [params[:email], session[:user]]) }
  session[:notice] = "設定を更新しました！"
  redirect '/'
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
    db.execute("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id) VALUES (?, ?, ?, ?, ?, ?)", 
               [session[:user], params[:drug_name], params[:message], params[:title], jst_time, p_id])
  end
  session[:notice] = "投稿が完了しました！"
  redirect (p_id == -1 ? '/' : "/post/#{p_id}")
end

get '/logout' do
  session.clear
  session[:notice] = "ログアウトしました"
  redirect '/'
end