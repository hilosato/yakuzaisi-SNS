Ruby
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
    db.execute "ALTER TABLE posts ADD COLUMN image_path TEXT;"
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
    .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
    .stat-box { background: #fbfbfd; padding: 15px; border-radius: 12px; text-align: center; flex: 1; border: 1px solid #d2d2d7; }
    .stat-num { display: block; font-size: 1.5rem; font-weight: 700; color: var(--primary); }
    .stat-label { font-size: 0.7rem; color: var(--secondary); font-weight: 600; }
    .menu-item { display: block; padding: 15px; background: var(--card); border-radius: 12px; margin-bottom: 10px; text-decoration: none; color: var(--text); font-weight: 600; border: 1px solid #d2d2d7; transition: 0.2s; }
    .menu-item:hover { background: #fbfbfd; border-color: var(--primary); }
    .tag { padding: 4px 8px; border-radius: 6px; font-size: 0.65rem; font-weight: 700; color: white; margin-right: 8px; }
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

# --- ホーム画面（タイトル・表題メイン） ---
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
      html += "
      <div class='post-card' style='padding: 20px;'>
        <div style='display:flex; justify-content:space-between; align-items:flex-start;'>
          <div style='flex: 1;'>
            <span class='tag' style='background:#{CATEGORIES[cat_name] || '#86868b'};'>#{cat_name}</span>
            <span style='color:var(--secondary); font-size:0.75rem;'>💊 #{row[2]}</span>
            <h3 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:var(--text);'>#{row[8]}</a></h3>
            <p style='color:var(--secondary); font-size:0.8rem; margin:0;'>👨‍⚕️ #{row[1]} | 📅 #{row[7].split(' ')[0]}</p>
          </div>
          <div style='text-align:right; margin-left:15px;'>
            <div style='font-size:0.85rem; color:var(--secondary);'>👍 #{row[3]}</div>
            <div style='font-size:0.85rem; color:var(--star);'>⭐️ #{row[4]}</div>
          </div>
        </div>
      </div>"
    end
  end
  html + "</div>"
end

# --- 投稿詳細（ここで内容と画像を表示） ---
get '/post/:id' do
  redirect '/login_page' unless session[:user]
  query do |db|
    post = db.execute("SELECT * FROM posts WHERE id = ?", [params[:id]]).first
    return header_menu + "<p>投稿が見つかりませんでした。</p></div>" unless post
    replies = db.execute("SELECT * FROM posts WHERE parent_id = ? ORDER BY id ASC", [params[:id]])
    is_liked = db.execute("SELECT id FROM likes_map WHERE user_name = ? AND post_id = ?", [session[:user], post[0]]).first
    is_starred = db.execute("SELECT id FROM stars_map WHERE user_name = ? AND post_id = ?", [session[:user], post[0]]).first
    l_class = is_liked ? "action-btn like-btn active" : "action-btn like-btn"
    s_class = is_starred ? "action-btn star-btn active" : "action-btn star-btn"
    
    html = header_menu + "<a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
      <div class='post-card' style='margin-top:20px;'>
        <span class='tag' style='background:#{CATEGORIES[post[10]] || '#86868b'};'>#{post[10]}</span>
        <h1 style='margin:10px 0;'>#{post[8]}</h1>
        <p style='color:var(--secondary); font-size:0.9rem;'>薬剤名: #{post[2]} | 投稿者: #{post[1]}</p>
        <hr style='border:0; border-top:1px solid #eee; margin:20px 0;'>"
    if post[9]
      html += "<div style='margin-bottom:20px;'><img src='/uploads/#{post[9]}' style='width:100%; border-radius:12px;'></div>"
    end
    html += "
        <div style='white-space: pre-wrap; font-size:1.05rem;'>#{post[5]}</div>
        <div style='display:flex; gap:10px; margin-top:30px;'>
          <form action='/post/#{post[0]}/like' method='post'><button type='submit' class='#{l_class}'>👍 役に立った！ (#{post[3]})</button></form>
          <form action='/post/#{post[0]}/star' method='post'><button type='submit' class='#{s_class}'>⭐️ お気に入り (#{post[4]})</button></form>
        </div>
        
        <div class='reply-form' style='margin-top:40px; padding-top:20px; border-top:1px solid #eee;'>
          <h4>💬 コメント・返信</h4>
          <form action='/post' method='post' enctype='multipart/form-data'>
            <input type='hidden' name='parent_id' value='#{post[0]}'>
            <input type='hidden' name='category' value='#{post[10]}'>
            <input type='hidden' name='drug_name' value='#{post[2]}'>
            <input type='hidden' name='title' value='Re: #{post[8]}'>
            <textarea name='message' placeholder='返信を入力...' required></textarea>
            <input type='file' name='image' accept='image/*'>
            <button type='submit' class='btn-primary'>返信を送信</button>
          </form>
        </div>
      </div>"
    
    replies.each do |r| 
      html += "
      <div class='post-card' style='margin-left: 30px; background:#fbfbfd;'>
        <strong>#{r[1]}</strong> <span style='color:var(--secondary); font-size:0.8rem;'>#{r[7]}</span>
        <p>#{r[5]}</p>"
      html += "<img src='/uploads/#{r[9]}' style='max-width:200px; border-radius:8px; display:block;'> " if r[9]
      html += "</div>"
    end
    html + "</div>"
  end
end

# --- 投稿保存ロジック ---
post '/post' do
  redirect '/login_page' unless session[:user]
  query do |db|
    user_info = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first
    if user_info.nil? || user_info[0].nil? || user_info[0].strip == ""
      session[:notice] = "投稿にはマイページからメールアドレスの登録が必要です"
      redirect '/profile'
      return
    end

    image_filename = nil
    if params[:image] && params[:image][:tempfile]
      image_filename = Time.now.to_i.to_s + "_" + params[:image][:filename]
      save_path = "./public/uploads/#{image_filename}"
      Dir.mkdir("./public/uploads") unless Dir.exist?("./public/uploads")
      File.open(save_path, 'wb') { |f| f.write(params[:image][:tempfile].read) }
    end

    jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')
    p_id = params[:parent_id].to_i
    db.execute("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id, category, image_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", 
               [session[:user], params[:drug_name], params[:message], params[:title], jst_time, p_id, params[:category], image_filename])
    
    new_id = db.last_insert_row_id
    redirect "/post/#{p_id == -1 ? new_id : p_id}"
  end
end

# --- マイページ ---
get '/profile' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<h1>マイページ</h1>"
  query do |db|
    user_row = db.execute("SELECT email FROM users WHERE user_name = ?", [session[:user]]).first
    current_email = user_row[0] || ""
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
    
    <div class='post-card'>
      <h4>👤 プロフィール編集</h4>
      <form action='/update_profile' method='post'>
        <label style='font-size:0.8rem;'>メールアドレス（投稿に必須）</label>
        <input type='email' name='email' value='#{current_email}' placeholder='example@mail.com' required>
        <button type='submit' class='btn-primary' style='width:auto;'>保存する</button>
      </form>
    </div>"
  end
  html + "</div>"
end

post '/update_profile' do
  redirect '/login_page' unless session[:user]
  query { |db| db.execute("UPDATE users SET email = ? WHERE user_name = ?", [params[:email], session[:user]]) }
  session[:notice] = "プロフィールを更新しました！"
  redirect '/profile'
end

# --- 認証 ---
post '/auth' do
  user_name, password, email, mode = params[:user_name], params[:password], params[:email], params[:mode]
  query do |db|
    user = db.execute("SELECT * FROM users WHERE user_name = ?", [user_name]).first
    if user
      if BCrypt::Password.new(user[2]) == password
        session[:user] = user_name
        redirect '/'
      else
        session[:notice] = "パス間違い"
        redirect '/login_page'
      end
    else
      hash_pass = BCrypt::Password.create(password)
      # modeがfullでemailがあれば保存
      saved_email = (mode == 'full') ? email : nil
      db.execute("INSERT INTO users (user_name, password_digest, email) VALUES (?, ?, ?)", [user_name, hash_pass, saved_email])
      session[:user] = user_name
      redirect '/'
    end
  end
end

get '/login_page' do
  header_menu + "
  <div class='post-card'>
    <h2>🔑 ログイン / 新規登録</h2>
    <form action='/auth' method='post' id='authForm'>
      <input type='text' name='user_name' id='userName' placeholder='名前' required>
      <input type='password' name='password' id='password' placeholder='パスワード' required>
      
      <div style='margin-top:20px; padding:15px; background:#f5f5f7; border-radius:12px;'>
        <button type='button' onclick='submitAs(\"guest\")' class='btn-primary' style='background:var(--secondary); width:100%;'>
          仮登録して閲覧する
        </button>
      </div>

      <div style='margin-top:20px; border-top:1px solid #d2d2d7; padding-top:20px;'>
        <label style='font-size:0.8rem; font-weight:bold;'>🌟 投稿・コメントもしたい方</label>
        <input type='email' name='email' id='emailField' placeholder='メールアドレス'>
        <button type='button' onclick='submitAs(\"full\")' class='btn-primary' style='width:100%; margin-top:10px;'>
          本登録する
        </button>
      </div>
      <input type='hidden' name='mode' id='submitMode'>
    </form>
  </div>
  <script>
    document.getElementById('authForm').onkeypress = function(e) { if (e.key === 'Enter') { e.preventDefault(); return false; } };
    function submitAs(mode) {
      const form = document.getElementById('authForm');
      if (!document.getElementById('userName').value || !document.getElementById('password').value) { form.reportValidity(); return; }
      if (mode === 'full' && document.getElementById('emailField').value.trim() === '') { alert('本登録にはメアドが必要です'); return; }
      document.getElementById('submitMode').value = mode;
      form.submit();
    }
  </script>"
end

# --- アクション ---
post '/post/:id/like' do
  redirect '/login_page' unless session[:user]
  query do |db|
    already = db.execute("SELECT id FROM likes_map WHERE user_name = ? AND post_id = ?", [session[:user], params[:id]]).first
    if already
      db.execute("DELETE FROM likes_map WHERE id = ?", [already[0]])
      db.execute("UPDATE posts SET likes = likes - 1 WHERE id = ?", [params[:id]])
    else
      db.execute("INSERT INTO likes_map (user_name, post_id) VALUES (?, ?)", [session[:user], params[:id]])
      db.execute("UPDATE posts SET likes = likes + 1 WHERE id = ?", [params[:id]])
    end
  end
  redirect back
end

post '/post/:id/star' do
  redirect '/login_page' unless session[:user]
  query do |db|
    already = db.execute("SELECT id FROM stars_map WHERE user_name = ? AND post_id = ?", [session[:user], params[:id]]).first
    if already
      db.execute("DELETE FROM stars_map WHERE id = ?", [already[0]])
      db.execute("UPDATE posts SET stars = stars - 1 WHERE id = ?", [params[:id]])
    else
      db.execute("INSERT INTO stars_map (user_name, post_id) VALUES (?, ?)", [session[:user], params[:id]])
      db.execute("UPDATE posts SET stars = stars + 1 WHERE id = ?", [params[:id]])
    end
  end
  redirect back
end

get '/logout' do
  session.clear
  redirect '/'
end

get '/post_new' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<h1>新しい知恵を共有</h1><div class='post-card'><form action='/post' method='post' enctype='multipart/form-data'><label>カテゴリ</label><select name='category'>"
  CATEGORIES.each { |name, color| html += "<option value='#{name}'>#{name}</option>" }
  html += "</select><input type='text' name='title' placeholder='表題（タイトル）' required><input type='text' name='drug_name' placeholder='薬剤名' required><label style='font-size:0.8rem; color:var(--secondary);'>📷 画像添付（任意）</label><input type='file' name='image' accept='image/*'><textarea name='message' placeholder='内容を入力...' rows='10' required></textarea><input type='hidden' name='parent_id' value='-1'><button type='submit' class='btn-primary'>投稿する</button></form></div></div>"
end