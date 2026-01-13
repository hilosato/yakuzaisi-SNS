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

# --- デザイン共通パーツ ---
def header_menu
  user_status = if session[:user]
    "<a href='/post_new' class='nav-link'>✍️ 投稿</a> <a href='/profile' class='nav-link'>👤 マイページ</a> <a href='/logout' class='nav-link'>ログアウト</a>"
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
    .stat-box { background: #fbfbfd; padding: 15px; border-radius: 12px; text-align: center; flex: 1; border: 1px solid #d2d2d7; }
    .stat-num { display: block; font-size: 1.5rem; font-weight: 700; color: var(--primary); }
    .stat-label { font-size: 0.7rem; color: var(--secondary); font-weight: 600; }
    .menu-item { display: block; padding: 15px; background: var(--card); border-radius: 12px; margin-bottom: 10px; text-decoration: none; color: var(--text); font-weight: 600; border: 1px solid #d2d2d7; transition: 0.2s; }
    .menu-item:hover { background: #fbfbfd; border-color: var(--primary); }
    .tag { padding: 4px 10px; border-radius: 6px; font-size: 0.75rem; font-weight: 700; color: white; margin-right: 8px; }
    .action-btn { background: none; border: 1px solid #d2d2d7; border-radius: 15px; padding: 4px 12px; cursor: pointer; font-size: 0.8rem; display: flex; align-items: center; gap: 4px; }
    .like-btn.active { background: #ffebeb; border-color: #ff3b30; color: #ff3b30; }
    .star-btn.active { background: #fff9eb; border-color: var(--star); color: var(--star); }
    .flash-notice { background: var(--accent); color: white; padding: 15px; text-align: center; font-weight: 600; }
    .btn-primary { background: var(--primary); color: white; border: none; padding: 12px 20px; border-radius: 10px; font-weight: 600; cursor: pointer; }
    input, textarea, select { width: 100%; padding: 12px; margin: 8px 0; border: 1px solid #d2d2d7; border-radius: 10px; box-sizing: border-box; }
  </style>
  <nav><a href='/' class='nav-brand'>PharmaShare</a><div class='nav-links'><a href='/' class='nav-link'>🏠 ホーム</a>#{user_status}</div></nav>
  #{flash_msg}
  <div class='container'>
  "
end

# --- ルート ---

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
      is_liked = session[:user] && db.execute("SELECT id FROM likes_map WHERE user_name = ? AND post_id = ?", [session[:user], row[0]]).first
      is_starred = session[:user] && db.execute("SELECT id FROM stars_map WHERE user_name = ? AND post_id = ?", [session[:user], row[0]]).first
      l_class = is_liked ? "action-btn like-btn active" : "action-btn like-btn"
      s_class = is_starred ? "action-btn star-btn active" : "action-btn star-btn"
      cat_name = row[10] || "その他"
      html += "
      <div class='post-card'>
        <span class='tag' style='background:#{CATEGORIES[cat_name] || '#86868b'};'>#{cat_name}</span>
        <span style='color:var(--secondary); font-size:0.8rem;'>💊 #{row[2]}</span>
        <h2 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:var(--text);'>#{row[8]}</a></h2>
        <div style='display:flex; justify-content:space-between; align-items:center;'>
          <p style='color:var(--secondary); font-size:0.85rem;'>👨‍⚕️ #{row[1]} | 📅 #{row[7]}</p>
          <div style='display:flex; gap:8px;'>
            <form action='/post/#{row[0]}/like' method='post' style='margin:0;'><button type='submit' class='#{l_class}'>👍 #{row[3]}</button></form>
            <form action='/post/#{row[0]}/star' method='post' style='margin:0;'><button type='submit' class='#{s_class}'>⭐️ #{row[4]}</button></form>
          </div>
        </div>
      </div>"
    end
  end
  html + "</div>"
end

# 詳細画面（ここでリプライのリプライを可能に修正）
get '/post/:id' do
  redirect '/login_page' unless session[:user]
  query do |db|
    post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first
    return header_menu + "<p>投稿なし</p></div>" unless post
    replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [params[:id]])
    is_liked = db.execute("SELECT id FROM likes_map WHERE user_name = ? AND post_id = ?", [session[:user], post[0]]).first
    is_starred = db.execute("SELECT id FROM stars_map WHERE user_name = ? AND post_id = ?", [session[:user], post[0]]).first
    l_class = is_liked ? "action-btn like-btn active" : "action-btn like-btn"
    s_class = is_starred ? "action-btn star-btn active" : "action-btn star-btn"
    
    html = header_menu + "<a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
      <div class='post-card' style='margin-top:20px;'>
        <div style='display:flex; justify-content:space-between;'><h1>#{post[8]}</h1>
        <div style='display:flex; gap:8px;'><form action='/post/#{post[0]}/like' method='post'><button type='submit' class='#{l_class}'>👍 #{post[3]}</button></form>
        <form action='/post/#{post[0]}/star' method='post'><button type='submit' class='#{s_class}'>⭐️ #{post[4]}</button></form></div></div>
        <div style='white-space: pre-wrap; margin:20px 0;'>#{post[5]}</div>
        <div class='reply-form'><h4>💬 コメント・返信を送る</h4><form action='/post' method='post'><input type='hidden' name='parent_id' value='#{post[0]}'><input type='hidden' name='category' value='#{post[10]}'><input type='hidden' name='drug_name' value='#{post[2]}'><input type='hidden' name='title' value='Re: #{post[8]}'><textarea name='message' required></textarea><button type='submit' class='btn-primary' style='width:auto;'>送信</button></form></div></div>"
    
    replies.each do |r| 
      html += "
      <div class='post-card' style='margin-left: 30px; background:#fbfbfd;'>
        <strong>#{r[1]}</strong> <span style='color:var(--secondary); font-size:0.8rem;'>#{r[7]}</span>
        <p>#{r[5]}</p>
        <a href='/post/#{r[0]}' style='font-size:0.8rem; color:var(--primary); text-decoration:none;'>↩︎ このコメントに返信する</a>
      </div>"
    end
    html + "</div>"
  end
end

# 認証（メアド必須化のバリデーション追加）
post '/auth' do
  user_name, password, email = params[:user_name], params[:password], params[:email]
  
  query do |db|
    user = db.execute("SELECT * FROM users WHERE user_name = ?", [user_name]).first
    if user
      if BCrypt::Password.new(user[2]) == password
        session[:user] = user_name
        redirect '/'
      else
        session[:notice] = "パスワード間違い"
        redirect '/login_page'
      end
    else
      # 新規登録時にメアドがない場合はエラー
      if email.nil? || email.strip == ""
        session[:notice] = "新規登録にはメールアドレスが必要です"
        redirect '/login_page'
      else
        hash_pass = BCrypt::Password.create(password)
        db.execute("INSERT INTO users (user_name, password_digest, email) VALUES (?, ?, ?)", [user_name, hash_pass, email])
        session[:user] = user_name
        redirect '/'
      end
    end
  end
end

get '/login_page' do
  header_menu + "<div class='post-card'><h2>🔑 ログイン / 新規登録</h2><p style='font-size:0.8rem; color:var(--secondary);'>※新規登録の方はメールアドレスも入力してください</p><form action='/auth' method='post'><input type='text' name='user_name' placeholder='名前' required><input type='password' name='password' placeholder='パスワード' required><input type='email' name='email' placeholder='メールアドレス（登録時必須）'><button type='submit' class='btn-primary' style='width:100%; margin-top:10px;'>ログイン・登録</button></form></div></div>"
end

# --- 他のルート（profile, my_posts, my_stars, logout等）は昨日のままでOK ---

get '/profile' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<h1>マイページ</h1>"
  query do |db|
    post_count = db.execute("SELECT COUNT(*) FROM posts WHERE user_name = ? AND parent_id = -1", [session[:user]]).first[0]
    total_likes = db.execute("SELECT SUM(likes) FROM posts WHERE user_name = ?", [session[:user]]).first[0] || 0
    total_stars = db.execute("SELECT SUM(stars) FROM posts WHERE user_name = ?", [session[:user]]).first[0] || 0
    html += "
    <div class='post-card'>
      <div style='text-align:center; margin-bottom:20px;'>
        <div style='width:60px; height:60px; background:var(--primary); color:white; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:1.5rem; margin: 0 auto 10px; font-weight:700;'>#{session[:user][0]}</div>
        <h3 style='margin:0;'>#{session[:user]} 先生</h3>
      </div>
      <div style='display:flex; gap:10px;'>
        <div class='stat-box'><span class='stat-num'>#{post_count}</span><span class='stat-label'>投稿数</span></div>
        <div class='stat-box'><span class='stat-num'>#{total_likes}</span><span class='stat-label'>もらった👍</span></div>
        <div class='stat-box'><span class='stat-num'>#{total_stars}</span><span class='stat-label'>もらった⭐️</span></div>
      </div>
    </div>
    <div style='margin-top:30px;'>
      <a href='/my_posts' class='menu-item'>📝 自分の投稿一覧を見る →</a>
      <a href='/my_stars' class='menu-item'>⭐️ お気に入り一覧を見る →</a>
    </div>"
  end
  html + "</div>"
end

get '/my_posts' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<a href='/profile' style='text-decoration:none; color:var(--primary); font-weight:600;'>← マイページへ</a><h1>📝 自分の投稿一覧</h1>"
  query do |db|
    db.execute("SELECT * FROM posts WHERE user_name = ? AND parent_id = -1 ORDER BY id DESC", [session[:user]]).each do |row|
      cat_name = row[10] || "その他"
      html += "<div class='post-card'><span class='tag' style='background:#{CATEGORIES[cat_name]};'>#{cat_name}</span><h3 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:var(--text);'>#{row[8]}</a></h3><p style='color:var(--secondary); font-size:0.8rem;'>📅 #{row[7]} | 👍 #{row[3]} ⭐️ #{row[4]}</p></div>"
    end
  end
  html + "</div>"
end

get '/my_stars' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<a href='/profile' style='text-decoration:none; color:var(--primary); font-weight:600;'>← マイページへ</a><h1>⭐️ お気に入り一覧</h1>"
  query do |db|
    db.execute("SELECT p.* FROM posts p JOIN stars_map s ON p.id = s.post_id WHERE s.user_name = ? ORDER BY s.id DESC", [session[:user]]).each do |row|
      cat_name = row[10] || "その他"
      html += "<div class='post-card'><span class='tag' style='background:#{CATEGORIES[cat_name]};'>#{cat_name}</span><h3 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:var(--text);'>#{row[8]}</a></h3><p style='color:var(--secondary); font-size:0.8rem;'>投稿者: #{row[1]} | 📅 #{row[7]} | 👍 #{row[3]} ⭐️ #{row[4]}</p></div>"
    end
  end
  html + "</div>"
end

get '/post_new' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<h1>新しい知恵を共有</h1><div class='post-card'><form action='/post' method='post'>"
  html += "<label>カテゴリ</label><select name='category'>"
  CATEGORIES.each { |name, color| html += "<option value='#{name}'>#{name}</option>" }
  html += "</select><input type='text' name='title' placeholder='タイトル' required><input type='text' name='drug_name' placeholder='薬剤名' required><textarea name='message' placeholder='内容を入力...' rows='10' required></textarea><input type='hidden' name='parent_id' value='-1'><button type='submit' class='btn-primary'>投稿する</button></form></div></div>"
end

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

post '/post' do
  redirect '/login_page' unless session[:user]
  jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')
  p_id = params[:parent_id].to_i
  new_id = nil
  query do |db|
    db.execute("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id, category) VALUES (?, ?, ?, ?, ?, ?, ?)", [session[:user], params[:drug_name], params[:message], params[:title], jst_time, p_id, params[:category]])
    new_id = db.last_insert_row_id
  end
  redirect "/post/#{p_id == -1 ? new_id : p_id}"
end

get '/logout' do
  session.clear
  redirect '/'
end