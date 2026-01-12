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

# --- デザイン ---
def header_menu
  user_status = if session[:user]
    "👤 #{session[:user]} さん | <a href='/logout' style='color:white;'>Logout</a>"
  else
    "<a href='/login_page' style='color:white;'>Login</a>"
  end

  "
  <style>
    body { font-family: 'Helvetica Neue', Arial, sans-serif; margin: 0; background-color: #f0f2f5; color: #1c1e21; }
    .container { max-width: 800px; margin: 0 auto; padding: 20px; }
    nav { background: #0077b6; padding: 10px 20px; display: flex; justify-content: space-between; align-items: center; position: sticky; top: 0; z-index: 100; }
    nav a { color: white; text-decoration: none; font-weight: bold; margin-right: 15px; }
    .post-card { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 1px 2px rgba(0,0,0,0.1); }
    .reply-card { background: #f9f9f9; padding: 15px; border-radius: 8px; margin-top: 10px; border-left: 4px solid #0077b6; margin-left: 20px; }
    .btn-like { background: #f0f2f5; border: none; padding: 8px 15px; border-radius: 5px; cursor: pointer; color: #65676b; }
    .post-img { max-width: 100%; border-radius: 8px; margin-top: 10px; }
    .btn-submit { background: #0077b6; color: white; border: none; padding: 12px; border-radius: 6px; cursor: pointer; width: 100%; }
    .login-bar { color: white; font-size: 0.9em; }
    input, textarea { width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 6px; box-sizing: border-box; }
  </style>
  <nav>
    <div>
      <a href='/'>🏠 Home</a>
      <a href='/post_new'>✍️ Post</a>
    </div>
    <div class='login-bar'>#{user_status}</div>
  </nav>
  <div class='container'>
  "
end

# --- ルート ---

get '/' do
  html = header_menu + "<h2>🏥 薬剤師の知恵フィード</h2>"
  query do |db|
    # 親投稿（返信じゃないもの）だけを取得
    db.execute("SELECT * FROM posts WHERE parent_id = -1 ORDER BY id DESC").each do |row|
      html += "
      <div class='post-card'>
        <div style='color:#65676b; font-size:0.8em;'>👨‍⚕️ #{row[1]} | 📅 #{row[6]}</div>
        <h3 style='margin:10px 0;'><a href='/post/#{row[0]}' style='text-decoration:none; color:black;'>#{row[7]}</a></h3>
        <p>💊 #{row[2]}</p>
        #{ row[9] ? "<img src='/uploads/#{row[9]}' class='post-img'>" : "" }
        <div style='margin-top:15px; display:flex; gap:10px;'>
          <form action='/like/#{row[0]}' method='post'>
            <button type='submit' class='btn-like'>❤️ #{row[3]}</button>
          </form>
          <a href='/post/#{row[0]}' class='btn-like' style='text-decoration:none;'>💬 返信・詳細</a>
        </div>
      </div>"
    end
  end
  html + "</div>"
end

get '/post_new' do
  unless session[:user]
    return header_menu + "<p>投稿するにはログインが必要です。</p><a href='/login_page'>ログイン画面へ</a></div>"
  end

  html = header_menu + "
  <div class='post-card'>
    <h2>✍️ 新規投稿</h2>
    <form action='/post' method='post' enctype='multipart/form-data'>
      <input type='hidden' name='user_name' value='#{session[:user]}'>
      <label>タイトル:</label><input type='text' name='title' required>
      <label>薬品名:</label><input type='text' name='drug_name' required>
      <label>内容:</label><textarea name='message' style='height:100px;' required></textarea>
      <label>📸 画像:</label><input type='file' name='myfile' accept='image/*'>
      <label>🔑 削除パスワード:</label><input type='password' name='password' required>
      <button type='submit' class='btn-submit'>🚀 投稿する</button>
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
    <div class='post-card'>
      <h1>#{post[7]}</h1>
      <p>👨‍⚕️ #{post[1]} | 📅 #{post[6]}</p>
      #{ post[9] ? "<img src='/uploads/#{post[9]}' class='post-img'>" : "" }
      <div style='margin:20px 0; line-height:1.8; white-space: pre-wrap;'>#{post[4]}</div>
    </div>
    
    <h3>💬 返信一覧</h3>"
    
  replies.each do |r|
    html += "
    <div class='reply-card'>
      <div style='font-size:0.8em; color:#65676b;'>👨‍⚕️ #{r[1]} | 📅 #{r[6]}</div>
      <div style='margin-top:5px;'>#{r[4]}</div>
    </div>"
  end

  # 返信フォーム
  if session[:user]
    html += "
    <div class='post-card' style='margin-top:30px;'>
      <h4>この投稿に返信する</h4>
      <form action='/post' method='post'>
        <input type='hidden' name='parent_id' value='#{post[0]}'>
        <input type='hidden' name='user_name' value='#{session[:user]}'>
        <input type='hidden' name='title' value='Re: #{post[7]}'>
        <input type='hidden' name='drug_name' value='#{post[2]}'>
        <textarea name='message' placeholder='返信内容を入力' required></textarea>
        <label>🔑 削除パスワード:</label><input type='password' name='password' required>
        <button type='submit' class='btn-submit' style='background:#555;'>返信する</button>
      </form>
    </div>"
  else
    html += "<p><a href='/login_page'>ログイン</a>すると返信できます。</p>"
  end
  
  html + "</div>"
end

# --- アクション ---

get '/login_page' do
  header_menu + "
    <div class='post-card'>
      <h2>🔑 ログイン</h2>
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