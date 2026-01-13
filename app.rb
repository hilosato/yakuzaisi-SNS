require 'sinatra'
require 'sqlite3'
require 'time'
require 'bcrypt'

# --- サーバー設定 ---
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

use Rack::Session::Cookie, :key => 'rack.session',
                           :path => '/',
                           :secret => 'katabami_pharmashare_2026_fixed_secret_key_long_long_long_long_64chars_over'

DB_NAME = "sns.db"

CATEGORIES = {
  "指導のコツ" => "#0071e3",
  "症例報告" => "#32d74b",
  "新薬情報" => "#ff9f0a",
  "その他" => "#86868b"
}

def setup_db
  db = SQLite3::Database.new DB_NAME
  db.execute "CREATE TABLE IF NOT EXISTS posts (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT, drug_name TEXT, likes INTEGER DEFAULT 0, stars INTEGER DEFAULT 0, message TEXT, parent_id INTEGER DEFAULT -1, created_at TEXT, title TEXT, image_path TEXT, category TEXT);"
  db.execute "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT UNIQUE, password_digest TEXT, email TEXT);"
  db.execute "CREATE TABLE IF NOT EXISTS likes_map (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT, post_id INTEGER);"
  db.execute "CREATE TABLE IF NOT EXISTS stars_map (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT, post_id INTEGER);"
  
  begin
    db.execute "ALTER TABLE posts ADD COLUMN stars INTEGER DEFAULT 0;"
  rescue SQLite3::SQLException
  end
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
    "<a href='/post_new' class='nav-link'>✍️ 投稿</a> <a href='/profile' class='nav-link'>👤 設定</a> <a href='/logout' class='nav-link'>ログアウト</a>"
  else
    "<a href='/login_page' class='nav-link'>ログイン / 登録</a>"
  end

  flash_msg = session[:notice] ? "<div class='flash-notice'>#{session[:notice]}</div>" : ""
  session[:notice] = nil

  "
  <style>
    :root { --primary: #0071e3; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --secondary: #86868b; --accent: #32d74b; --star: #ff9f0a; }
    body { font-family: -apple-system, sans-serif; margin: 0; background: var(--bg); color: var(--text); line-height: 1.5; }
    .container { max-width: 700px; margin: 0 auto; padding: 40px 20px; }
    nav { background: rgba(255, 255, 255, 0.8); backdrop-filter: blur(20px); padding: 12px 20px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0,0,0,0.1); position: sticky; top: 0; z-index: 100; }
    .nav-brand { font-weight: 700; color: var(--primary); text-decoration: none; font-size: 1.2rem; }
    .nav-link { color: var(--text); text-decoration: none; font-size: 0.9rem; margin-left: 15px; font-weight: 500; }
    .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .reply-card { background: #fbfbfd; border-left: 4px solid #d2d2d7; padding: 15px; margin-top: 10px; border-radius: 0 12px 12px 0; }
    .grandchild-card { margin-left: 30px; border-left: 3px solid var(--primary); background: #f5f5f7; padding: 10px; margin-top: 5px; border-radius: 0 8px 8px 0; font-size: 0.9rem; }
    .btn-primary { background: var(--primary); color: white; border: none; padding: 10px 20px; border-radius: 980px; cursor: pointer; font-weight: 600; text-decoration: none; display: inline-block; font-size: 0.85rem; }
    .action-btn { background: none; border: 1px solid #d2d2d7; border-radius: 15px; padding: 4px 12px; cursor: pointer; font-size: 0.8rem; transition: all 0.2s; display: flex; align-items: center; gap: 4px; }
    .like-btn.active { background: #ffebeb; border-color: #ff3b30; color: #ff3b30; }
    .star-btn.active { background: #fff9eb; border-color: var(--star); color: var(--star); }
    .flash-notice { background: var(--accent); color: white; padding: 15px; text-align: center; font-weight: 600; }
    .tag { padding: 4px 10px; border-radius: 6px; font-size: 0.75rem; font-weight: 700; color: white; margin-right: 8px; }
    input, textarea, select { width: 100%; padding: 12px; margin: 8px 0; border: 1px solid #d2d2d7; border-radius: 10px; box-sizing: border-box; }
    .reply-form { margin-top: 10px; padding-top: 10px; border-top: 1px dashed #d2d2d7; }
  </style>
  <nav><a href='/' class='nav-brand'>PharmaShare</a><div class='nav-links'><a href='/' class='nav-link'>🏠 ホーム</a>#{user_status}</div></nav>
  #{flash_msg}
  <div class='container'>
  "
end

# --- ルート設定 ---

post '/post/:id/like' do
  redirect '/login_page' unless session[:user]
  post_id, user = params[:id], session[:user]
  query do |db|
    already = db.execute("SELECT id FROM likes_map WHERE user_name = ? AND post_id = ?", [user, post_id]).first
    if already
      db.execute("DELETE FROM likes_map WHERE id = ?", [already[0]])
      db.execute("UPDATE posts SET likes = likes - 1 WHERE id = ?", [post_id])
    else
      db.execute("INSERT INTO likes_map (user_name, post_id) VALUES (?, ?)", [user, post_id])
      db.execute("UPDATE posts SET likes = likes + 1 WHERE id = ?", [post_id])
    end
  end
  redirect back
end

post '/post/:id/star' do
  redirect '/login_page' unless session[:user]
  post_id, user = params[:id], session[:user]
  query do |db|
    already = db.execute("SELECT id FROM stars_map WHERE user_name = ? AND post_id = ?", [user, post_id]).first
    if already
      db.execute("DELETE FROM stars_map WHERE id = ?", [already[0]])
      db.execute("UPDATE posts SET stars = stars - 1 WHERE id = ?", [post_id])
    else
      db.execute("INSERT INTO stars_map (user_name, post_id) VALUES (?, ?)", [user, post_id])
      db.execute("UPDATE posts SET stars = stars + 1 WHERE id = ?", [post_id])
    end
  end
  redirect back
end

get '/' do
  word = params[:search]
  html = header_menu + "<h1>最新の知恵</h1>"
  html += "<form action='/' method='get' style='display:flex; gap:10px; margin-bottom:20px;'><input type='text' name='search' placeholder='キーワード検索...' value='#{word}'><button type='submit' class='btn-primary' style='width:80px;'>検索</button></form>"
  query do |db|
    sql = "SELECT * FROM posts WHERE (parent_id = -1 OR parent_id = '-1') ORDER BY id DESC"
    sql_params = []
    if word && word != ""
      sql = "SELECT * FROM posts WHERE (parent_id = -1 OR parent_id = '-1') AND (title LIKE ? OR drug_name LIKE ? OR message LIKE ?) ORDER BY id DESC"
      sql_params = ["%#{word}%", "%#{word}%", "%#{word}%"]
    end
    
    db.execute(sql, sql_params).each do |row|
      cat_name = row[10] || "その他"
      likes_count = row[3] || 0
      stars_count = row[4] || 0
      is_liked = session[:user] && db.execute("SELECT id FROM likes_map WHERE user_name = ? AND post_id = ?", [session[:user], row[0]]).first
      is_starred = session[:user] && db.execute("SELECT id FROM stars_map WHERE user_name = ? AND post_id = ?", [session[:user], row[0]]).first
      
      l_class = is_liked ? "action-btn like-btn active" : "action-btn like-btn"
      s_class = is_starred ? "action-btn star-btn active" : "action-btn star-btn"

      html += "
      <div class='post-card'>
        <span class='tag' style='background:#{CATEGORIES[cat_name] || '#86868b'};'>#{cat_name}</span>
        <span style='color:var(--secondary); font-size:0.8rem;'>💊 #{row[2]}</span>
        <h2 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:var(--text);'>#{row[8]}</a></h2>
        <div style='display:flex; justify-content:space-between; align-items:center;'>
          <p style='color:var(--secondary); font-size:0.85rem;'>👨‍⚕️ #{row[1]} | 📅 #{row[7]}</p>
          <div style='display:flex; gap:8px;'>
            <form action='/post/#{row[0]}/like' method='post' style='margin:0;'><button type='submit' class='#{l_class}'>👍 #{likes_count}</button></form>
            <form action='/post/#{row[0]}/star' method='post' style='margin:0;'><button type='submit' class='#{s_class}'>⭐️ #{stars_count}</button></form>
          </div>
        </div>
      </div>"
    end
  end
  html + "</div>"
end

get '/post/:id' do
  redirect '/login_page' unless session[:user]
  post, replies = nil, []
  query do |db|
    post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first
    replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [params[:id]])
    
    unless post
      return header_menu + "<p>投稿が見つかりませんでした。</p><a href='/'>ホームへ戻る</a></div>"
    end

    cat_name = post[10] || "その他"
    is_liked = db.execute("SELECT id FROM likes_map WHERE user_name = ? AND post_id = ?", [session[:user], post[0]]).first
    is_starred = db.execute("SELECT id FROM stars_map WHERE user_name = ? AND post_id = ?", [session[:user], post[0]]).first
    
    l_class = is_liked ? "action-btn like-btn active" : "action-btn like-btn"
    s_class = is_starred ? "action-btn star-btn active" : "action-btn star-btn"

    html = header_menu + "
      <a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
      <div class='post-card' style='margin-top:20px;'>
        <div style='display:flex; justify-content:space-between; align-items:flex-start;'>
          <h1>#{post[8]}</h1>
          <div style='display:flex; gap:8px; margin-top:10px;'>
            <form action='/post/#{post[0]}/like' method='post'><button type='submit' class='#{l_class}'>👍 #{post[3]}</button></form>
            <form action='/post/#{post[0]}/star' method='post'><button type='submit' class='#{s_class}'>⭐️ #{post[4]}</button></form>
          </div>
        </div>
        <div style='line-height:1.8; white-space: pre-wrap; margin:20px 0;'>#{post[5]}</div>
        <div class='reply-form'>
          <h4>💬 この投稿にコメント</h4>
          <form action='/post' method='post'><input type='hidden' name='parent_id' value='#{post[0]}'><input type='hidden' name='category' value='#{cat_name}'><input type='hidden' name='drug_name' value='#{post[2]}'><input type='hidden' name='title' value='Re: #{post[8]}'><textarea name='message' placeholder='コメントを入力...' required></textarea><button type='submit' class='btn-primary'>コメントを送る</button></form>
        </div>
      </div>"

    replies.each do |r|
      grand_replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [r[0]])
      html += "
      <div class='reply-card'>
        <div style='display:flex; justify-content:space-between;'>
          <strong>👨‍⚕️ #{r[1]}</strong>
          <span style='font-size:0.7rem; color:var(--secondary);'>#{r[7]}</span>
        </div>
        <p>#{r[5]}</p>
        <details style='margin-top:5px; font-size:0.8rem;'>
          <summary style='cursor:pointer; color:var(--primary);'>リプライする</summary>
          <form action='/post' method='post' class='reply-form'><input type='hidden' name='parent_id' value='#{r[0]}'><input type='hidden' name='category' value='#{cat_name}'><input type='hidden' name='drug_name' value='#{post[2]}'><input type='hidden' name='title' value='Re: #{r[1]}さんへ'><textarea name='message' placeholder='#{r[1]}さんに返信...' required></textarea><button type='submit' class='btn-primary'>リプライを送る</button></form>
        </details>"

      grand_replies.each do |gr|
        html += "<div class='grandchild-card'><strong>↪️ #{gr[1]}</strong>: #{gr[5]} <span style='font-size:0.65rem; color:var(--secondary); float:right;'>#{gr[7]}</span></div>"
      end
      html += "</div>"
    end
    html + "</div>"
  end
end

get '/post_new' do
  redirect '/login_page' unless session[:user]
  cat_options = CATEGORIES.keys.map { |c| "<option value='#{c}'>#{c}</option>" }.join
  header_menu + "<div class='post-card'><h2>✍️ 新規投稿</h2><form action='/post' method='post'><input type='hidden' name='parent_id' value='-1'><label>カテゴリ</label><select name='category'>#{cat_options}</select><label>タイトル</label><input type='text' name='title' required><label>薬品名</label><input type='text' name='drug_name' required><label>内容</label><textarea name='message' style='height:150px;' required></textarea><button type='submit' class='btn-primary' style='width:100%; font-size:1.1rem;'>公開する</button></form></div></div>"
end

get '/profile' do
  redirect '/login_page' unless session[:user]
  user_email = nil
  query { |db| user_email = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first&.at(0) }
  header_menu + "<div class='post-card'><h2>👤 設定</h2><p>ユーザー名: <strong>#{session[:user]}</strong></p><form action='/update_profile' method='post'><label>メールアドレス</label><input type='email' name='email' value='#{user_email}' required><button type='submit' class='btn-primary' style='background:var(--accent); width:100%;'>保存する</button></form></div></div>"
end

post '/update_profile' do
  query { |db| db.execute("UPDATE users SET email = ? WHERE user_name = ?", [params[:email], session[:user]]) }
  session[:notice] = "設定を保存しました"
  redirect '/'
end

post '/auth' do
  user_name, password = params[:user_name], params[:password]
  query do |db|
    user = db.execute("SELECT * FROM users WHERE user_name = ?", [user_name]).first
    if user
      if BCrypt::Password.new(user[2]) == password
        session[:user] = user_name
        redirect '/'
      else
        session[:notice] = "パスワードが違います"
        redirect '/login_page'
      end
    else
      hash_pass = BCrypt::Password.create(password)
      db.execute("INSERT INTO users (user_name, password_digest) VALUES (?, ?)", [user_name, hash_pass])
      session[:user] = user_name
      redirect '/'
    end
  end
end

get '/login_page' do
  header_menu + "<div class='post-card' style='max-width:400px; margin: 0 auto;'><h2>🔑 ログイン</h2><form action='/auth' method='post'><input type='text' name='user_name' placeholder='名前' required><input type='password' name='password' placeholder='パスワード' required><button type='submit' class='btn-primary' style='width:100%;'>ログイン・登録</button></form></div></div>"
end

post '/post' do
  redirect '/login_page' unless session[:user]
  jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')
  p_id = params[:parent_id].to_i
  
  new_post_id = nil
  query do |db|
    db.execute("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id, category) VALUES (?, ?, ?, ?, ?, ?, ?)", 
               [session[:user], params[:drug_name], params[:message], params[:title], jst_time, p_id, params[:category]])
    new_post_id = db.last_insert_row_id
  end
  redirect "/post/#{p_id == -1 ? new_post_id : p_id}"
end

get '/logout' do
  session.clear
  redirect '/'
end