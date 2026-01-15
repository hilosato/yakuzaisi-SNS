require 'sinatra'
require 'pg'
require 'time'
require 'bcrypt'
require 'uri'
require 'cgi'

# --- サーバー設定 ---
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

use Rack::Session::Cookie, :key => 'rack.session',
                           :path => '/',
                           :secret => 'katabami_pharmashare_2026_fixed_secret_key_64chars_over'

# --- データベース接続設定 ---
def db_connection
  db_url = ENV['DATABASE_URL']
  uri = URI.parse(db_url || 'postgres://localhost/pharmashare')
  PG.connect(host: uri.host, port: uri.port, dbname: uri.path[1..-1], user: uri.user, password: uri.password, connect_timeout: 10)
end

# テーブル作成 & カラム追加
def setup_db
  conn = db_connection
  conn.exec "CREATE TABLE IF NOT EXISTS posts (id SERIAL PRIMARY KEY, user_name TEXT, drug_name TEXT, likes INTEGER DEFAULT 0, stars INTEGER DEFAULT 0, message TEXT, parent_id INTEGER DEFAULT -1, created_at TEXT, title TEXT, image_path TEXT, category TEXT);"
  conn.exec "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, user_name TEXT UNIQUE, password_digest TEXT, email TEXT);"
  conn.exec "CREATE TABLE IF NOT EXISTS likes_map (id SERIAL PRIMARY KEY, user_name TEXT, post_id INTEGER);"
  conn.exec "CREATE TABLE IF NOT EXISTS stars_map (id SERIAL PRIMARY KEY, user_name TEXT, post_id INTEGER);"
  
  # 自己紹介とアイコン用のカラムを追加（エラー回避のためbegin-rescueを使用）
  begin
    conn.exec "ALTER TABLE users ADD COLUMN bio TEXT;"
    conn.exec "ALTER TABLE users ADD COLUMN icon_path TEXT;"
  rescue
    # すでにカラムがある場合は何もしない
  end
  conn.close
rescue => e
  puts "DB Setup Error: #{e.message}"
end
setup_db

def query(sql, params = [])
  conn = db_connection
  res = conn.exec_params(sql, params)
  yield res if block_given?
ensure
  conn.close if conn
end

CATEGORIES = {
  "インシデントレポート" => "#ff3b30",
  "疑義紹介、処方介入事例" => "#0071e3",
  "適正使用するためのメモ" => "#64d2ff",
  "他職種連携事例" => "#5856d6",
  "往診同行" => "#32d74b",
  "保険関連" => "#ff9f0a",
  "部下後輩教育" => "#af52de",
  "その他独り言" => "#8e8e93"
}

def highlight(text, word)
  return CGI.escapeHTML(text) if word.nil? || word.empty?
  escaped_text = CGI.escapeHTML(text)
  escaped_word = CGI.escapeHTML(word)
  escaped_text.gsub(/(#{Regexp.escape(escaped_word)})/i, '<mark style="background-color: #ffef00; color: black; padding: 0 2px; border-radius: 4px;">\1</mark>')
end

# --- デザイン共通パーツ ---
def header_menu
  user_status = if session[:user]
    "<a href='/post_new' class='nav-link'>✍️ 投稿</a> <a href='/profile/#{session[:user]}' class='nav-link'>👤 マイページ</a> <a href='/logout' class='nav-link'>ログアウト</a>"
  else
    "<a href='/login_page' class='nav-link'>ログイン / 登録</a>"
  end
  flash_msg = session[:notice] ? "<div class='flash-notice'>#{session[:notice]}</div>" : ""
  session[:notice] = nil
  "
  <!DOCTYPE html>
  <html lang='ja'>
  <head>
    <meta charset='UTF-8'>
    <title>PharmaShare</title>
    <style>
      :root { --primary: #0071e3; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --secondary: #86868b; --accent: #32d74b; --star: #ff9f0a; }
      body { font-family: -apple-system, sans-serif; margin: 0; background: var(--bg); color: var(--text); line-height: 1.6; font-size: 17px; }
      .container { max-width: 700px; margin: 0 auto; padding: 40px 20px; }
      nav { background: rgba(255, 255, 255, 0.8); backdrop-filter: blur(20px); padding: 12px 20px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0,0,0,0.1); position: sticky; top: 0; z-index: 100; }
      .nav-brand { font-weight: 700; color: var(--primary); text-decoration: none; font-size: 1.3rem; }
      .nav-link { color: var(--text); text-decoration: none; font-size: 1rem; margin-left: 15px; font-weight: 500; }
      .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
      .tag { padding: 4px 10px; border-radius: 6px; font-size: 0.75rem; font-weight: 700; color: white; margin-right: 8px; text-decoration: none; }
      .user-icon { width: 50px; height: 50px; border-radius: 50%; object-fit: cover; background: #ddd; vertical-align: middle; border: 1px solid #eee; }
      .btn-primary { background: var(--primary); color: white; border: none; padding: 12px 20px; border-radius: 10px; font-weight: 600; cursor: pointer; font-size: 1rem; }
      input, textarea, select { width: 100%; padding: 12px; margin: 10px 0; border: 1px solid #d2d2d7; border-radius: 10px; box-sizing: border-box; font-size: 1rem; }
      .flash-notice { background: var(--accent); color: white; padding: 15px; text-align: center; font-weight: 600; }
    </style>
  </head>
  <body>
    <nav><a href='/' class='nav-brand'>PharmaShare</a><div class='nav-links'><a href='/' class='nav-link'>🏠 ホーム</a>#{user_status}</div></nav>
    #{flash_msg}
    <div class='container'>
  "
end

# --- ホーム画面（カテゴリ検索対応） ---
get '/' do
  word = params[:search]
  cat_filter = params[:category]
  html = header_menu + "<h1>最新の知恵</h1>"
  
  html += "
    <form action='/' method='get' class='post-card' style='display:flex; flex-direction:column; gap:10px;'>
      <input type='text' name='search' placeholder='キーワード検索...' value='#{CGI.escapeHTML(word.to_s)}'>
      <select name='category'>
        <option value=''>すべてのカテゴリ</option>
        #{CATEGORIES.map{|name, _| \"<option value='\#{name}' \#{'selected' if cat_filter == name}>\#{name}</option>\"}.join}
      </select>
      <button type='submit' class='btn-primary'>絞り込み検索</button>
    </form>"
  
  sql = "SELECT * FROM posts WHERE (parent_id = -1) "
  sql_params = []
  param_idx = 1
  
  if word && word != ""
    sql += \"AND (title LIKE $\#{param_idx} OR drug_name LIKE $\#{param_idx} OR message LIKE $\#{param_idx}) \"
    sql_params << \"%\#{word}%\"
    param_idx += 1
  end
  
  if cat_filter && cat_filter != ""
    sql += \"AND category = $\#{param_idx} \"
    sql_params << cat_filter
  end
  
  sql += "ORDER BY id DESC"

  query(sql, sql_params) do |res|
    res.each do |row|
      cat_name = row['category'] || "その他独り言"
      display_title = highlight(row['title'], word)
      display_drug = highlight(row['drug_name'], word)
      
      html += "
      <div class='post-card'>
        <div style='display:flex; justify-content:space-between; align-items:flex-start;'>
          <div style='flex: 1;'>
            <a href='/?category=\#{CGI.escape(cat_name)}' class='tag' style='background:\#{CATEGORIES[cat_name] || '#8e8e93'};'>\#{cat_name}</a>
            <span style='color:var(--secondary); font-size:0.85rem;'>💊 \#{display_drug}</span>
            <h3 style='margin:10px 0;'><a href='/post/\#{row['id']}' style='text-decoration:none; color:var(--text);'>\#{display_title}</a></h3>
            <p style='color:var(--secondary); font-size:0.9rem; margin:0;'>
              <a href='/profile/\#{row['user_name']}' style='text-decoration:none; color:var(--primary); font-weight:600;'>👨‍⚕️ \#{row['user_name']}</a> | 📅 \#{row['created_at'].split(' ')[0]}
            </p>
          </div>
        </div>
      </div>"
    end
  end
  html + "</div>"
end




# --- 投稿詳細 ---
get '/post/:id' do
  redirect '/login_page' unless session[:user]
  query("SELECT * FROM posts WHERE id = $1", [params[:id]]) do |res|
    post = res.first
    return header_menu + "<p>投稿が見つかりませんでした。</p></div>" unless post
    
    replies = []
    query("SELECT * FROM posts WHERE parent_id = $1 ORDER BY id ASC", [params[:id]]) { |r_res| replies = r_res.to_a }
    
    is_liked = false
    is_starred = false
    query("SELECT id FROM likes_map WHERE user_name = $1 AND post_id = $2", [session[:user], post['id']]) { |r| is_liked = true if r.any? }
    query("SELECT id FROM stars_map WHERE user_name = $1 AND post_id = $2", [session[:user], post['id']]) { |r| is_starred = true if r.any? }
    
    l_class = is_liked ? "action-btn like-btn active" : "action-btn like-btn"
    s_class = is_starred ? "action-btn star-btn active" : "action-btn star-btn"
    
    html = header_menu + "<a href='/' style='text-decoration:none; color:var(--primary); font-weight:600;'>← 戻る</a>
      <div class='post-card' style='margin-top:20px;'>
        <div style='display:flex; justify-content:space-between; align-items:center;'>
          <span class='tag' style='background:#{CATEGORIES[post['category']] || '#8e8e93'};'>#{post['category']}</span>
          #{post['user_name'] == session[:user] ? "<a href='/post/#{post['id']}/edit' style='font-size:0.9rem; color:var(--primary); text-decoration:none;'>✏️ 編集する</a>" : ""}
        </div>
        <h1 style='margin:10px 0;'>#{CGI.escapeHTML(post['title'])}</h1>
        <p style='color:var(--secondary); font-size:1rem;'>薬剤名: #{CGI.escapeHTML(post['drug_name'])} | 投稿者: <a href='/profile/#{post['user_name']}' style='color:var(--primary); text-decoration:none; font-weight:600;'>#{post['user_name']}</a></p>
        <hr style='border:0; border-top:1px solid #eee; margin:20px 0;'>"
    if post['image_path'] && post['image_path'] != ""
      html += "<div style='margin-bottom:20px;'><img src='/uploads/#{post['image_path']}' style='width:100%; border-radius:12px;'></div>"
    end
    html += "
        <div style='white-space: pre-wrap; font-size:1.1rem;'>#{CGI.escapeHTML(post['message'])}</div>
        <div style='display:flex; gap:10px; margin-top:30px;'>
          <form action='/post/#{post['id']}/like' method='post'><button type='submit' class='#{l_class}'>👍 役に立った！ (#{post['likes']})</button></form>
          <form action='/post/#{post['id']}/star' method='post'><button type='submit' class='#{s_class}'>⭐️ お気に入り (#{post['stars']})</button></form>
        </div>
      </div>"

    html += "
      <div class='post-card' style='margin-top:20px;'>
        <h4>💬 コメント・返信</h4>
        <form action='/post' method='post' enctype='multipart/form-data'>
          <input type='hidden' name='parent_id' value='#{post['id']}'>
          <input type='hidden' name='category' value='#{post['category']}'>
          <input type='hidden' name='drug_name' value='#{post['drug_name']}'>
          <input type='hidden' name='title' value='Re: #{post['title']}'>
          <textarea name='message' placeholder='返信を入力...' required></textarea>
          <input type='file' name='image' accept='image/*'>
          <button type='submit' class='btn-primary'>返信を送信</button>
        </form>
      </div>"
    
    replies.each do |r| 
      img_tag = (r['image_path'] && r['image_path'] != "") ? "<img src='/uploads/#{r['image_path']}' style='max-width:200px; border-radius:8px; display:block;'>" : ""
      html += "
      <div class='post-card' style='margin-left: 30px; background:#fbfbfd;'>
        <div style='display:flex; justify-content:space-between;'>
          <div>
            <a href='/profile/#{r['user_name']}' style='text-decoration:none; color:var(--primary); font-weight:600;'>#{r['user_name']}</a> <span style='color:var(--secondary); font-size:0.9rem;'>#{r['created_at']}</span>
          </div>
        </div>
        <p style='font-size:1rem;'>#{CGI.escapeHTML(r['message'])}</p>
        #{img_tag}
      </div>"
    end
    html + "</div>"
  end
end

# --- ②③ マイページ ---
get '/profile/:user_name' do
  target_user = params[:user_name]
  u_info = nil
  query("SELECT * FROM users WHERE user_name = $1", [target_user]) { |res| u_info = res.first }
  return header_menu + "ユーザーが見つかりません</div>" unless u_info

  post_count, total_likes = 0, 0
  query("SELECT COUNT(*) FROM posts WHERE user_name = $1 AND parent_id = -1", [target_user]) { |res| post_count = res.first['count'] }
  query("SELECT SUM(likes) as l FROM posts WHERE user_name = $1", [target_user]) { |res| total_likes = res.first['l'] || 0 }

  is_mine = (session[:user] == target_user)
  icon_src = (u_info['icon_path'] && u_info['icon_path'] != "") ? "/uploads/#{u_info['icon_path']}" : "https://ui-avatars.com/api/?name=#{CGI.escape(target_user)}&background=random"

  bio_text = (u_info['bio'] && u_info['bio'] != "") ? CGI.escapeHTML(u_info['bio']) : "自己紹介はまだありません。"

  html = header_menu + "
    <div class='post-card' style='text-align:center;'>
      <img src='#{icon_src}' class='user-icon' style='width:100px; height:100px; margin-bottom:15px;'>
      <h2 style='margin:0;'>#{target_user} 先生</h2>
      <div style='display:flex; gap:10px; justify-content:center; margin:15px 0;'>
        <div style='background:#f5f5f7; padding:10px 20px; border-radius:10px;'><small>投稿数</small><br><strong>#{post_count}</strong></div>
        <div style='background:#f5f5f7; padding:10px 20px; border-radius:10px;'><small>獲得👍</small><br><strong>#{total_likes}</strong></div>
      </div>
      <div style='text-align:left; background:#fafafa; padding:20px; border-radius:12px; margin-top:15px; border:1px solid #eee;'>
        <h4 style='margin-top:0;'>自己紹介</h4>
        <div style='white-space: pre-wrap;'>#{bio_text}</div>
      </div>"
  
  if is_mine
    html += "
      <div style='margin-top:20px; display:flex; gap:10px; justify-content:center;'>
        <a href='/profile_edit' class='btn-primary' style='text-decoration:none;'>プロフィール編集</a>
        <a href='/my_favorites' class='btn-primary' style='text-decoration:none; background:var(--star);'>⭐️ お気に入り</a>
      </div>"
  end
  
  html += "</div><h3>📝 #{target_user} 先生の投稿一覧</h3>"

  query("SELECT * FROM posts WHERE user_name = $1 AND parent_id = -1 ORDER BY id DESC", [target_user]) do |res|
    if res.any?
      res.each do |row|
        html += "<div class='post-card'><a href='/post/#{row['id']}' style='text-decoration:none; color:var(--text); font-weight:bold;'>#{CGI.escapeHTML(row['title'])}</a><br><small style='color:var(--secondary);'>#{row['created_at']}</small></div>"
      end
    else
      html += "<p>まだ投稿がありません。</p>"
    end
  end
  html + "</div>"
end

# プロフィール編集
get '/profile_edit' do
  redirect '/login_page' unless session[:user]
  u_info = nil
  query("SELECT * FROM users WHERE user_name = $1", [session[:user]]) { |res| u_info = res.first }
  header_menu + "
    <h1>プロフィール編集</h1>
    <div class='post-card'>
      <form action='/profile_update' method='post' enctype='multipart/form-data'>
        <label style='font-weight:bold;'>アイコン画像</label>
        <input type='file' name='icon' accept='image/*'>
        <label style='font-weight:bold;'>自己紹介文</label>
        <textarea name='bio' rows='6' placeholder='例：病棟業務メインの薬剤師です。'>#{u_info['bio']}</textarea>
        <label style='font-weight:bold;'>メールアドレス</label>
        <input type='email' name='email' value='#{u_info['email']}' required>
        <button type='submit' class='btn-primary' style='width:100%; margin-top:20px;'>保存する</button>
      </form>
      <a href='/profile/#{session[:user]}' style='display:block; text-align:center; margin-top:15px; color:var(--secondary); text-decoration:none;'>キャンセル</a>
    </div>
  </div>"
end

post '/profile_update' do
  redirect '/login_page' unless session[:user]
  icon_filename = nil
  if params[:icon] && params[:icon][:tempfile]
    icon_filename = "icon_" + Time.now.to_i.to_s + "_" + params[:icon][:filename].gsub(/\s+/, '_')
    File.open("./public/uploads/#{icon_filename}", 'wb') { |f| f.write(params[:icon][:tempfile].read) }
  end
  if icon_filename
    query("UPDATE users SET email = $1, bio = $2, icon_path = $3 WHERE user_name = $4", [params[:email], params[:bio], icon_filename, session[:user]])
  else
    query("UPDATE users SET email = $1, bio = $2 WHERE user_name = $3", [params[:email], params[:bio], session[:user]])
  end
  session[:notice] = "プロフィールを更新しました！"
  redirect "/profile/#{session[:user]}"
end

# --- お気に入り一覧 ---
get '/my_favorites' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<h1>⭐️ お気に入り</h1>"
  sql = "SELECT p.* FROM posts p JOIN stars_map s ON p.id = s.post_id WHERE s.user_name = $1 ORDER BY s.id DESC"
  query(sql, [session[:user]]) do |res|
    if res.any?
      res.each do |row|
        cat_name = row['category'] || "その他独り言"
        html += "
        <div class='post-card'>
          <span class='tag' style='background:#{CATEGORIES[cat_name] || '#8e8e93'};'>#{cat_name}</span>
          <h3 style='margin:10px 0;'><a href='/post/#{row['id']}' style='text-decoration:none; color:var(--text);'>#{CGI.escapeHTML(row['title'])}</a></h3>
          <p style='color:var(--secondary); font-size:0.9rem;'>👨‍⚕️ #{row['user_name']} | 📅 #{row['created_at']}</p>
        </div>"
      end
    else
      html += "<p>お気に入りした投稿はまだありません。</p>"
    end
  end
  html + "</div>"
end

# --- 投稿・編集・削除 ---
post '/post' do
  redirect '/login_page' unless session[:user]
  user_email = nil
  query("SELECT email FROM users WHERE user_name = $1", [session[:user]]) { |res| user_email = res.first['email'] if res.any? }
  if user_email.nil? || user_email.strip == ""
    session[:notice] = "投稿にはメールアドレスの登録が必要です"
    redirect '/profile_edit'
    return
  end
  image_filename = ""
  if params[:image] && params[:image][:tempfile]
    image_filename = Time.now.to_i.to_s + "_" + params[:image][:filename].gsub(/\s+/, '_')
    Dir.mkdir("./public/uploads") unless Dir.exist?("./public/uploads")
    File.open("./public/uploads/#{image_filename}", 'wb') { |f| f.write(params[:image][:tempfile].read) }
  end
  jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')
  p_id = params[:parent_id].to_i
  query("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id, category, image_path) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)", 
         [session[:user], params[:drug_name], params[:message], params[:title], jst_time, p_id, params[:category], image_filename])
  redirect p_id == -1 ? '/' : "/post/#{p_id}"
end

get '/post_new' do
  redirect '/login_page' unless session[:user]
  cat_options = CATEGORIES.map { |name, _| "<option value='#{name}'>#{name}</option>" }.join
  header_menu + "
    <h1>新しい知恵を共有</h1>
    <div class='post-card'>
      <form action='/post' method='post' enctype='multipart/form-data'>
        <label>カテゴリ</label>
        <select name='category'>#{cat_options}</select>
        <input type='text' name='title' placeholder='表題（タイトル）' required>
        <input type='text' name='drug_name' placeholder='薬剤名' required>
        <label style='font-size:0.9rem; color:var(--secondary);'>📷 画像添付（任意）</label>
        <input type='file' name='image' accept='image/*'>
        <textarea name='message' placeholder='内容を入力...' rows='10' required></textarea>
        <input type='hidden' name='parent_id' value='-1'>
        <button type='submit' class='btn-primary' style='width:100%;'>投稿する</button>
      </form>
    </div>
  </div>"
end

get '/post/:id/edit' do
  redirect '/login_page' unless session[:user]
  query("SELECT * FROM posts WHERE id = $1", [params[:id]]) do |res|
    post = res.first
    if post && post['user_name'] == session[:user]
      cat_options = CATEGORIES.map { |name, _| "<option value='#{name}' #{'selected' if post['category'] == name}>#{name}</option>" }.join
      header_menu + "
        <h1>投稿を編集</h1>
        <div class='post-card'>
          <form action='/post/#{post['id']}/update' method='post'>
            <label>カテゴリ</label>
            <select name='category'>#{cat_options}</select>
            <input type='text' name='title' value='#{CGI.escapeHTML(post['title'])}' required>
            <input type='text' name='drug_name' value='#{CGI.escapeHTML(post['drug_name'])}' required>
            <textarea name='message' rows='10' required>#{CGI.escapeHTML(post['message'])}</textarea>
            <button type='submit' class='btn-primary' style='width:100%;'>更新する</button>
          </form>
          <a href='javascript:history.back()' style='display:block; text-align:center; margin-top:15px; color:var(--secondary); text-decoration:none;'>キャンセル</a>
        </div>
      </div>"
    else
      redirect '/'
    end
  end
end

post '/post/:id/update' do
  query("UPDATE posts SET category = $1, title = $2, drug_name = $3, message = $4 WHERE id = $5", [params[:category], params[:title], params[:drug_name], params[:message], params[:id]])
  redirect "/post/#{params[:id]}"
end

# --- 認証 ---
get '/login_page' do
  header_menu + "
    <div style='max-width: 500px; margin: 0 auto;'>
      <div class='post-card'>
        <h2 style='text-align: center; color: var(--primary);'>🔑 PharmaShare</h2>
        <form action='/auth' method='post'>
          <input type='text' name='user_name' placeholder='ユーザー名' required>
          <input type='password' name='password' placeholder='パスワード' required>
          <button type='submit' class='btn-primary' style='width:100%;'>ログイン / 新規登録</button>
        </form>
        <p style='font-size:0.8rem; color:var(--secondary); text-align:center;'>※ユーザー名がなければ自動で新規登録されます</p>
      </div>
    </div></div>"
end

post '/auth' do
  user_name, password = params[:user_name], params[:password]
  user = nil
  query("SELECT * FROM users WHERE user_name = $1", [user_name]) { |res| user = res.first }
  if user
    if BCrypt::Password.new(user['password_digest']) == password
      session[:user] = user_name
      redirect '/'
    else
      session[:notice] = "パスワードが違います"
      redirect '/login_page'
    end
  else
    hash_pass = BCrypt::Password.create(password)
    query("INSERT INTO users (user_name, password_digest) VALUES ($1, $2)", [user_name, hash_pass])
    session[:user] = user_name
    redirect '/'
  end
end

get '/logout' do
  session.clear
  redirect '/'
end

# --- いいね・スター ---
post '/post/:id/like' do
  redirect '/login_page' unless session[:user]
  query("SELECT id FROM likes_map WHERE user_name = $1 AND post_id = $2", [session[:user], params[:id]]) do |res|
    if res.any?
      query("DELETE FROM likes_map WHERE user_name = $1 AND post_id = $2", [session[:user], params[:id]])
      query("UPDATE posts SET likes = likes - 1 WHERE id = $1", [params[:id]])
    else
      query("INSERT INTO likes_map (user_name, post_id) VALUES ($1, $2)", [session[:user], params[:id]])
      query("UPDATE posts SET likes = likes + 1 WHERE id = $1", [params[:id]])
    end
  end
  redirect back
end

post '/post/:id/star' do
  redirect '/login_page' unless session[:user]
  query("SELECT id FROM stars_map WHERE user_name = $1 AND post_id = $2", [session[:user], params[:id]]) do |res|
    if res.any?
      query("DELETE FROM stars_map WHERE user_name = $1 AND post_id = $2", [session[:user], params[:id]])
      query("UPDATE posts SET stars = stars - 1 WHERE id = $1", [params[:id]])
    else
      query("INSERT INTO stars_map (user_name, post_id) VALUES ($1, $2)", [session[:user], params[:id]])
      query("UPDATE posts SET stars = stars + 1 WHERE id = $1", [params[:id]])
    end
  end
  redirect back
end

get '/robots.txt' do
  content_type 'text/plain'
  "User-agent: *\nAllow: /"
end