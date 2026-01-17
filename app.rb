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
                           :secret => 'katabami_pharmashare_2026_fixed_secret_key_long_long_long_long_64chars_over'

# --- データベース接続設定 ---
def db_connection
  db_url = ENV['DATABASE_URL']
  uri = URI.parse(db_url || 'postgres://localhost/pharmashare')
  
  PG.connect(
    host: uri.host,
    port: uri.port,
    dbname: uri.path[1..-1],
    user: uri.user,
    password: uri.password,
    connect_timeout: 10
  )
end

# テーブル作成
def setup_db
  conn = db_connection
  # 既存のテーブル作成
  conn.exec "CREATE TABLE IF NOT EXISTS posts (id SERIAL PRIMARY KEY, user_name TEXT, drug_name TEXT, likes INTEGER DEFAULT 0, stars INTEGER DEFAULT 0, message TEXT, parent_id INTEGER DEFAULT -1, created_at TEXT, title TEXT, image_path TEXT, category TEXT);"
  conn.exec "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, user_name TEXT UNIQUE, password_digest TEXT, email TEXT);"
  conn.exec "CREATE TABLE IF NOT EXISTS likes_map (id SERIAL PRIMARY KEY, user_name TEXT, post_id INTEGER);"
  conn.exec "CREATE TABLE IF NOT EXISTS stars_map (id SERIAL PRIMARY KEY, user_name TEXT, post_id INTEGER);"

  # 【ここが重要！】 bioカラムがなければ追加する命令
  conn.exec "ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT;"
  
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

# ① カテゴリ追加（適正使用するためのメモを追加）
CATEGORIES = {
  "インシデントレポート" => "#ff3b30",
  "疑義紹介、処方介入事例" => "#0071e3",
  "適正使用するためのメモ" => "#64d2ff", # 追加項目（空色）
  "他職種連携事例" => "#5856d6",
  "往診同行" => "#32d74b",
  "保険関連" => "#ff9f0a",
  "部下後輩教育" => "#af52de",
  "その他独り言" => "#8e8e93"
}

# ③ 検索ハイライト用ヘルパー
def highlight(text, word)
  return CGI.escapeHTML(text) if word.nil? || word.empty?
  escaped_text = CGI.escapeHTML(text)
  escaped_word = CGI.escapeHTML(word)
  # 大文字小文字を区別せず、マッチした部分を <mark> タグで囲む
  escaped_text.gsub(/(#{Regexp.escape(escaped_word)})/i, '<mark style="background-color: #ffef00; color: black; padding: 0 2px; border-radius: 4px;">\1</mark>')
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
  <!DOCTYPE html>
  <html lang='ja'>
  <head>
    <meta charset='UTF-8'>
    <meta name='google-site-verification' content='Se2VtZahtpBZH-XnXQg_alFiqWcxyz6ywgjswLJ5Cmc' />
    <title>PharmaShare - 薬剤師専用SNS｜現場の知恵と経験が集まる場所</title>
    <meta name='description' content='インシデント事例、疑義紹介、他職種連携から部下教育まで。教科書には載っていない「日常の忙しさに埋もれてしまう貴重な気づきと経験」を共有する薬剤師専用SNS。日々の業務に直結する知恵を、発信して共有しよう。'>
    <style>
      :root { --primary: #0071e3; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --secondary: #86868b; --accent: #32d74b; --star: #ff9f0a; }
      /* ② 文字サイズ全体を少し大きく修正 (16px -> 17px) */
      body { font-family: -apple-system, sans-serif; margin: 0; background: var(--bg); color: var(--text); line-height: 1.6; font-size: 17px; }
      .container { max-width: 700px; margin: 0 auto; padding: 40px 20px; }
      nav { background: rgba(255, 255, 255, 0.8); backdrop-filter: blur(20px); padding: 12px 20px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0,0,0,0.1); position: sticky; top: 0; z-index: 100; }
      .nav-brand { font-weight: 700; color: var(--primary); text-decoration: none; font-size: 1.3rem; }
      .nav-link { color: var(--text); text-decoration: none; font-size: 1rem; margin-left: 15px; font-weight: 500; }
      .post-card { background: var(--card); padding: 24px; border-radius: 18px; margin-bottom: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
      .stat-box { background: #fbfbfd; padding: 15px; border-radius: 12px; text-align: center; flex: 1; border: 1px solid #d2d2d7; }
      .stat-num { display: block; font-size: 1.6rem; font-weight: 700; color: var(--primary); }
      .stat-label { font-size: 0.8rem; color: var(--secondary); font-weight: 600; }
      .tag { padding: 4px 10px; border-radius: 6px; font-size: 0.75rem; font-weight: 700; color: white; margin-right: 8px; }
      .action-btn { background: none; border: 1px solid #d2d2d7; border-radius: 15px; padding: 6px 14px; cursor: pointer; font-size: 0.9rem; display: flex; align-items: center; gap: 4px; }
      .btn-primary { background: var(--primary); color: white; border: none; padding: 14px 22px; border-radius: 10px; font-weight: 600; cursor: pointer; font-size: 1rem; }
      input, textarea, select { width: 100%; padding: 14px; margin: 10px 0; border: 1px solid #d2d2d7; border-radius: 10px; box-sizing: border-box; font-size: 1rem; }
      h1 { font-size: 1.8rem; }
      h3 { font-size: 1.3rem; }
    </style>
  </head>
  <body>
    <nav><a href='/' class='nav-brand'>PharmaShare</a><div class='nav-links'><a href='/' class='nav-link'>🏠 ホーム</a>#{user_status}</div></nav>
    #{flash_msg}
    <div class='container'>
  "
end

# --- ホーム画面 ---
get '/' do
  word = params[:search]
  selected_cat = params[:category] # 追加：カテゴリを受け取る
  
  html = header_menu + "<h1>最新の知恵</h1>"
  
  # カテゴリ選択ボタンの表示
  html += "<div style='margin-bottom: 20px; display: flex; flex-wrap: wrap; gap: 8px;'>"
  html += "<a href='/' style='text-decoration:none; padding: 6px 12px; border-radius: 20px; font-size: 0.85rem; border: 1px solid #ddd; background: #{selected_cat ? 'white' : '#eee'}; color: #{selected_cat ? '#666' : 'black'}; font-weight: bold;'>すべて</a>"
  CATEGORIES.each do |name, color|
    is_active = (selected_cat == name)
    bg_color = is_active ? color : "white"
    text_color = is_active ? "white" : "#666"
    html += "<a href='/?category=#{CGI.escape(name)}' style='text-decoration:none; padding: 6px 12px; border-radius: 20px; font-size: 0.85rem; border: 1px solid #{color}; background: #{bg_color}; color: #{text_color}; font-weight: bold;'>#{name}</a>"
  end
  html += "</div>"

  html += "<form action='/' method='get' style='display:flex; gap:10px; margin-bottom:20px;'><input type='text' name='search' placeholder='キーワード検索...' value='#{CGI.escapeHTML(word.to_s)}'><button type='submit' class='btn-primary' style='width:100px;'>検索</button></form>"
  
  # DBクエリの組み立て
  sql = "SELECT * FROM posts WHERE (parent_id = -1) "
  sql_params = []
  
  # キーワード検索がある場合
  if word && word != ""
    sql += "AND (title LIKE $#{sql_params.size + 1} OR drug_name LIKE $#{sql_params.size + 1} OR message LIKE $#{sql_params.size + 1}) "
    sql_params << "%#{word}%"
  end
  
  # カテゴリ検索がある場合（追加）
  if selected_cat && selected_cat != ""
    sql += "AND (category = $#{sql_params.size + 1}) "
    sql_params << selected_cat
  end
  
  sql += "ORDER BY id DESC"

  query(sql, sql_params) do |res|
    # (以下、投稿表示のループ部分は今のコードと同じでOK！)
    res.each do |row|
      cat_name = row['category'] || "その他独り言"
      display_title = highlight(row['title'], word)
      display_drug = highlight(row['drug_name'], word)
      
      html += "
      <div class='post-card' style='padding: 20px;'>
        <div style='display:flex; justify-content:space-between; align-items:flex-start;'>
          <div style='flex: 1;'>
            <span class='tag' style='background:#{CATEGORIES[cat_name] || '#8e8e93'};'>#{cat_name}</span>
            <span style='color:var(--secondary); font-size:0.85rem;'>💊 #{display_drug}</span>
            <h3 style='margin:10px 0;'><a href='/post/#{row['id']}' style='text-decoration:none; color:var(--text);'>#{display_title}</a></h3>
            <p style='color:var(--secondary); font-size:0.9rem; margin:0;'>
                  👨‍⚕️ <a href='/profile/#{row['user_name']}' style='text-decoration:none; color:var(--primary); font-weight:600;'>#{row['user_name']}</a> | 📅 #{row['created_at'].split(' ')[0]}
            </p>
          </div>
          <div style='text-align:right; margin-left:15px;'>
            <div style='font-size:1rem; color:var(--secondary);'>👍 #{row['likes']}</div>
            <div style='font-size:1rem; color:var(--star);'>⭐️ #{row['stars']}</div>
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
        <p style='color:var(--secondary); font-size:1rem;'>薬剤名: #{CGI.escapeHTML(post['drug_name'])} | 投稿者: #{post['user_name']}</p>
        <hr style='border:0; border-top:1px solid #eee; margin:20px 0;'>"
    if post['image_path'] && post['image_path'] != ""
      html += "<div style='margin-bottom:20px;'><img src='/uploads/#{post['image_path']}' style='width:100%; border-radius:12px;'></div>"
    end
    html += "
        <div style='white-space: pre-wrap; font-size:1.1rem;'>#{CGI.escapeHTML(post['message'])}</div>
        <div style='display:flex; gap:10px; margin-top:30px;'>
          <form action='/post/#{post['id']}/like' method='post'><button type='submit' class='#{l_class}'>👍 役に立った！ (#{post['likes']})</button></form>
          <form action='/post/#{post['id']}/star' method='post'><button type='submit' class='#{s_class}'>⭐️ お気に入り (#{post['stars']})</button></form>
        </div>"
        
    if post['user_name'] == session[:user]
      html += "
      <form action='/post/#{post['id']}/delete' method='post' style='margin-top:20px;' onsubmit='return confirm(\"本当に削除しますか？\");'>
        <button type='submit' style='background:none; border:none; color:#ff3b30; cursor:pointer; font-size:0.9rem; font-weight:600; padding:0;'>🗑️ この投稿を削除する</button>
      </form>"
    end

    html += "
        <div class='reply-form' style='margin-top:40px; padding-top:20px; border-top:1px solid #eee;'>
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
        </div>
      </div>"
    
    replies.each do |r| 
      html += "
      <div class='post-card' style='margin-left: 30px; background:#fbfbfd;'>
        <div style='display:flex; justify-content:space-between;'>
          <div>
            <strong>#{r['user_name']}</strong> <span style='color:var(--secondary); font-size:0.9rem;'>#{r['created_at']}</span>
          </div>
          <div style='display:flex; gap:10px;'>"
      if r['user_name'] == session[:user]
        html += "
        <a href='/post/#{r['id']}/edit' style='font-size:0.8rem; color:var(--primary); text-decoration:none;'>編集</a>
        <form action='/post/#{r['id']}/delete' method='post' onsubmit='return confirm(\"この返信を削除しますか？\");'>
          <button type='submit' style='background:none; border:none; color:#ff3b30; cursor:pointer; font-size:0.8rem;'>削除</button>
        </form>"
      end
      html += "
          </div>
        </div>
        <p style='font-size:1rem;'>#{CGI.escapeHTML(r['message'])}</p>"
      html += "<img src='/uploads/#{r['image_path']}' style='max-width:200px; border-radius:8px; display:block;'> " if r['image_path'] && r['image_path'] != ""
      html += "</div>"
    end
    html + "</div>"
  end
end

# --- 編集画面 ---
get '/post/:id/edit' do
  redirect '/login_page' unless session[:user]
  query("SELECT * FROM posts WHERE id = $1", [params[:id]]) do |res|
    post = res.first
    if post && post['user_name'] == session[:user]
      html = header_menu + "<h1>投稿を編集</h1><div class='post-card'><form action='/post/#{post['id']}/update' method='post' enctype='multipart/form-data'><label>カテゴリ</label><select name='category'>"
      CATEGORIES.each { |name, color| html += "<option value='#{name}' #{'selected' if post['category'] == name}>#{name}</option>" }
      html += "</select><input type='text' name='title' value='#{CGI.escapeHTML(post['title'])}' placeholder='表題' required><input type='text' name='drug_name' value='#{CGI.escapeHTML(post['drug_name'])}' placeholder='薬剤名' required><textarea name='message' placeholder='内容を入力...' rows='10' required>#{CGI.escapeHTML(post['message'])}</textarea><button type='submit' class='btn-primary'>更新する</button><a href='javascript:history.back()' style='display:block; text-align:center; margin-top:15px; color:var(--secondary); text-decoration:none; font-size:1rem;'>キャンセル</a></form></div></div>"
      html
    else
      session[:notice] = "編集権限がありません。"
      redirect '/'
    end
  end
end

# --- 編集保存 ---
post '/post/:id/update' do
  redirect '/login_page' unless session[:user]
  query("SELECT user_name, parent_id FROM posts WHERE id = $1", [params[:id]]) do |res|
    post = res.first
    if post && post['user_name'] == session[:user]
      query("UPDATE posts SET category = $1, title = $2, drug_name = $3, message = $4 WHERE id = $5", 
            [params[:category], params[:title], params[:drug_name], params[:message], params[:id]])
      session[:notice] = "更新しました！"
      redirect post['parent_id'].to_i == -1 ? "/post/#{params[:id]}" : "/post/#{post['parent_id']}"
    else
      session[:notice] = "編集権限がありません。"
      redirect '/'
    end
  end
end

# --- 投稿・画像保存 ---
post '/post' do
  redirect '/login_page' unless session[:user]
  
  user_email = nil
  query("SELECT email FROM users WHERE user_name = $1", [session[:user]]) { |res| user_email = res.first['email'] if res.any? }
  
  if user_email.nil? || user_email.strip == ""
    session[:notice] = "投稿にはマイページからメールアドレスの登録が必要です"
    redirect '/profile'
    return
  end

  image_filename = ""
  if params[:image] && params[:image][:tempfile]
    image_filename = Time.now.to_i.to_s + "_" + params[:image][:filename]
    save_path = "./public/uploads/#{image_filename}"
    Dir.mkdir("./public/uploads") unless Dir.exist?("./public/uploads")
    File.open(save_path, 'wb') { |f| f.write(params[:image][:tempfile].read) }
  end

  jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')
  p_id = params[:parent_id].to_i
  
  query("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id, category, image_path) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)", 
         [session[:user], params[:drug_name], params[:message], params[:title], jst_time, p_id, params[:category], image_filename])
  
  redirect p_id == -1 ? '/' : "/post/#{p_id}"
end

# --- 削除機能 ---
post '/post/:id/delete' do
  redirect '/login_page' unless session[:user]
  query("SELECT user_name, parent_id FROM posts WHERE id = $1", [params[:id]]) do |res|
    post = res.first
    if post && post['user_name'] == session[:user]
      parent_id = post['parent_id'].to_i
      query("DELETE FROM likes_map WHERE post_id = $1", [params[:id]])
      query("DELETE FROM stars_map WHERE post_id = $1", [params[:id]])
      query("DELETE FROM posts WHERE id = $1", [params[:id]])
      session[:notice] = "削除しました。"
      redirect parent_id == -1 ? '/' : "/post/#{parent_id}"
    else
      session[:notice] = "権限がありません。"
      redirect '/'
    end
  end
end

# --- マイページ（プロフィール） ---
get '/profile' do
  redirect '/login_page' unless session[:user]
  
  current_email, current_bio, post_count, total_likes, total_stars = "", "", 0, 0, 0
  query("SELECT email, bio FROM users WHERE user_name = $1", [session[:user]]) do |res| 
    if res.any?
      current_email = res.first['email']
      current_bio = res.first['bio']
    end
  end
  query("SELECT COUNT(*) FROM posts WHERE user_name = $1 AND parent_id = -1", [session[:user]]) { |res| post_count = res.first['count'] }
  query("SELECT SUM(likes) as l, SUM(stars) as s FROM posts WHERE user_name = $1", [session[:user]]) do |res| 
    total_likes = res.first['l'] || 0
    total_stars = res.first['s'] || 0
  end

  html = header_menu + "
    <h1>マイページ</h1>
    
    <div class='post-card'>
      <div style='text-align:center; margin-bottom:20px;'>
        <div style='width:70px; height:70px; background:var(--primary); color:white; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:1.8rem; margin: 0 auto 10px; font-weight:700;'>#{session[:user][0]}</div>
        <h3 style='margin:0;'>#{session[:user]} 先生</h3>
        <p><a href='/profile/#{session[:user]}' style='font-size:0.8rem; color:var(--primary);'>公開プロフィールを確認する</a></p>
      </div>
      <div style='display:flex; gap:10px;'>
        <div class='stat-box'><span class='stat-num'>#{post_count}</span><span class='stat-label'>投稿数</span></div>
        <div class='stat-box'><span class='stat-num'>#{total_likes}</span><span class='stat-label'>もらった👍</span></div>
        <div class='stat-box'><span class='stat-num'>#{total_stars}</span><span class='stat-label'>もらった⭐️</span></div>
      </div>
    </div>

    <div class='post-card' style='display: flex; flex-direction: column; gap: 10px;'>
      <h4>🔍 コンテンツを確認する</h4>
      <a href='/my_posts' class='btn-primary' style='text-decoration: none; text-align: center; background: #3498db;'>📝 自分の投稿一覧</a>
      <a href='/my_favorites' class='btn-primary' style='text-decoration: none; text-align: center; background: var(--star);'>⭐️ お気に入りした投稿</a>
    </div>

    <div class='post-card'>
      <h4>👤 プロフィール編集</h4>
      <form action='/update_profile' method='post'>
        <label style='font-size:0.9rem;'>自己紹介（キャリアや得意分野など）</label>
        <textarea name='bio' placeholder='例：門前で5年勤務しています。漢方が得意です。' rows='4'>#{current_bio}</textarea>
        
        <label style='font-size:0.9rem;'>メールアドレス（投稿に必須）</label>
        <input type='email' name='email' value='#{current_email}' placeholder='example@mail.com' required>
        
        <button type='submit' class='btn-primary' style='width:auto; margin-top:10px;'>プロフィールを保存</button>
      </form>
      <div style='margin-top: 20px; text-align: center;'>
        <a href='/logout' style='color: #e74c3c; font-size: 0.9rem; text-decoration: none;'>🚪 ログアウト</a>
      </div>
    </div>
  </div>"
end

# --- 自分の投稿一覧 ---
get '/my_posts' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<h1>📝 自分の投稿</h1>"
  query("SELECT * FROM posts WHERE user_name = $1 AND parent_id = -1 ORDER BY id DESC", [session[:user]]) do |res|
    if res.any?
      res.each do |row|
        cat_name = row['category'] || "その他独り言"
        html += "
        <div class='post-card' style='padding: 20px;'>
          <span class='tag' style='background:#{CATEGORIES[cat_name] || '#8e8e93'};'>#{cat_name}</span>
          <h3 style='margin:10px 0;'><a href='/post/#{row['id']}' style='text-decoration:none; color:var(--text);'>#{CGI.escapeHTML(row['title'])}</a></h3>
          <p style='color:var(--secondary); font-size:0.9rem;'>📅 #{row['created_at']}</p>
        </div>"
      end
    else
      html += "<p>まだ投稿がありません。</p>"
    end
  end
  html + "</div>"
end

# --- お気に入り（スター）した投稿一覧 ---
get '/my_favorites' do
  redirect '/login_page' unless session[:user]
  html = header_menu + "<h1>⭐️ お気に入り</h1>"
  sql = "SELECT p.* FROM posts p JOIN stars_map s ON p.id = s.post_id WHERE s.user_name = $1 ORDER BY s.id DESC"
  query(sql, [session[:user]]) do |res|
    if res.any?
      res.each do |row|
        cat_name = row['category'] || "その他独り言"
        html += "
        <div class='post-card' style='padding: 20px;'>
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

post '/update_profile' do
  redirect '/login_page' unless session[:user]
  query("UPDATE users SET email = $1 WHERE user_name = $2", [params[:email], session[:user]])
  session[:notice] = "プロフィールを更新しました！"
  redirect '/profile'
end

# --- 認証 ---
post '/auth' do
  user_name, password, email, mode = params[:user_name], params[:password], params[:email], params[:mode]
  user = nil
  query("SELECT * FROM users WHERE user_name = $1", [user_name]) { |res| user = res.first if res.any? }

  if mode == 'login'
    # ログインモードの場合
    if user
      if BCrypt::Password.new(user['password_digest']) == password
        session[:user] = user_name
        redirect '/'
      else
        session[:notice] = "パスワードが間違っています。"
        redirect '/login_page'
      end
    else
      session[:notice] = "ユーザーが見つかりません。新規登録してください。"
      redirect '/login_page'
    end
  else
    # 新規登録モードの場合 (signup)
    if user
      # ★ ここでチェック！
      session[:notice] = "「#{user_name}」はすでに登録されています。別の名前を試してください。"
      redirect '/login_page'
    else
      hash_pass = BCrypt::Password.create(password)
      saved_email = (mode == 'full') ? email : nil
      query("INSERT INTO users (user_name, password_digest, email) VALUES ($1, $2, $3)", [user_name, hash_pass, saved_email])
      session[:user] = user_name
      redirect '/'
    end
  end
end

get '/login_page' do
  header_menu + "
    <div class='container' style='max-width: 500px;'>
      <div class='post-card'>
        <h2 style='text-align: center; color: var(--primary);'>🔑 PharmaShareへようこそ</h2>
        <p style='font-size: 0.95rem; color: var(--secondary); text-align: center; margin-bottom: 30px;'>
          薬剤師の知恵を共有し、現場をより良くするコミュニティ
        </p>

        <div style='display: flex; border-bottom: 1px solid #d2d2d7; margin-bottom: 20px;'>
          <button onclick='showAuth(\"login\")' id='tab-login' style='flex: 1; padding: 10px; border: none; background: none; font-weight: bold; border-bottom: 2px solid var(--primary); cursor: pointer; font-size: 1rem;'>ログイン</button>
          <button onclick='showAuth(\"signup\")' id='tab-signup' style='flex: 1; padding: 10px; border: none; background: none; color: var(--secondary); cursor: pointer; font-size: 1rem;'>新規登録</button>
        </div>

        <form action='/auth' method='post' id='authForm'>
          <input type='text' name='user_name' id='userName' placeholder='ユーザー名' required>
          <input type='password' name='password' id='password' placeholder='パスワード' required>
          
          <div id='signup-extras' style='display: none; margin-top: 10px; padding: 15px; background: #fdfaf0; border-radius: 12px; border: 1px solid #faecc5;'>
            <label style='font-size: 0.95rem; font-weight: bold; color: #856404;'>🌟 本登録のメリット</label>
            <ul style='font-size: 0.85rem; color: #856404; margin: 8px 0; padding-left: 20px;'>
              <li>知恵を投稿して仲間に共有できる</li>
              <li>「お気に入り」を保存して後で見返せる</li>
              <li>自分の投稿実績がマイページに残る</li>
            </ul>
            <input type='email' name='email' id='emailField' placeholder='メールアドレス（本登録用）'>
            <p style='font-size: 0.8rem; color: var(--secondary); margin-top: 5px;'>※閲覧のみ（仮登録）の方は空欄でOKです</p>
          </div>

          <input type='hidden' name='mode' id='submitMode' value='login'>
          
          <button type='button' id='main-btn' onclick='handleAuth()' class='btn-primary' style='width: 100%; margin-top: 20px;'>ログインする</button>
        </form>
      </div>
    </div>

    <script>
      function showAuth(mode) {
        const signupExtras = document.getElementById('signup-extras');
        const mainBtn = document.getElementById('main-btn');
        const tabLogin = document.getElementById('tab-login');
        const tabSignup = document.getElementById('tab-signup');
        const submitMode = document.getElementById('submitMode');

        if (mode === 'signup') {
          signupExtras.style.display = 'block';
          mainBtn.innerText = 'アカウントを作成する';
          tabSignup.style.borderBottom = '2px solid var(--primary)';
          tabSignup.style.fontWeight = 'bold';
          tabSignup.style.color = 'var(--text)';
          tabLogin.style.borderBottom = 'none';
          tabLogin.style.fontWeight = 'normal';
          tabLogin.style.color = 'var(--secondary)';
          submitMode.value = 'signup';
        } else {
          signupExtras.style.display = 'none';
          mainBtn.innerText = 'ログインする';
          tabLogin.style.borderBottom = '2px solid var(--primary)';
          tabLogin.style.fontWeight = 'bold';
          tabLogin.style.color = 'var(--text)';
          tabSignup.style.borderBottom = 'none';
          tabSignup.style.fontWeight = 'normal';
          tabSignup.style.color = 'var(--secondary)';
          submitMode.value = 'login';
        }
      }

      function handleAuth() {
        const form = document.getElementById('authForm');
        const mode = document.getElementById('submitMode').value;
        const email = document.getElementById('emailField').value;

        if (!document.getElementById('userName').value || !document.getElementById('password').value) {
          form.reportValidity();
          return;
        }

        if (mode === 'signup') {
          document.getElementById('submitMode').value = (email.trim() !== '') ? 'full' : 'guest';
        }
        form.submit();
      }
    </script>
  "
end

# --- いいね・スター機能 ---
post '/post/:id/like' do
  redirect '/login_page' unless session[:user]
  post_id = params[:id].to_i
  already = false
  query("SELECT id FROM likes_map WHERE user_name = $1 AND post_id = $2", [session[:user], post_id]) { |r| already = true if r.any? }
  if already
    query("DELETE FROM likes_map WHERE user_name = $1 AND post_id = $2", [session[:user], post_id])
    query("UPDATE posts SET likes = likes - 1 WHERE id = $1", [post_id])
  else
    query("INSERT INTO likes_map (user_name, post_id) VALUES ($1, $2)", [session[:user], post_id])
    query("UPDATE posts SET likes = likes + 1 WHERE id = $1", [post_id])
  end
  redirect back
end

post '/post/:id/star' do
  redirect '/login_page' unless session[:user]
  post_id = params[:id].to_i
  already = false
  query("SELECT id FROM stars_map WHERE user_name = $1 AND post_id = $2", [session[:user], post_id]) { |r| already = true if r.any? }
  if already
    query("DELETE FROM stars_map WHERE user_name = $1 AND post_id = $2", [session[:user], post_id])
    query("UPDATE posts SET stars = stars - 1 WHERE id = $1", [post_id])
  else
    query("INSERT INTO stars_map (user_name, post_id) VALUES ($1, $2)", [session[:user], post_id])
    query("UPDATE posts SET stars = stars + 1 WHERE id = $1", [post_id])
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
  html += "</select><input type='text' name='title' placeholder='表題（タイトル）' required><input type='text' name='drug_name' placeholder='薬剤名' required><label style='font-size:0.9rem; color:var(--secondary);'>📷 画像添付（任意）</label><input type='file' name='image' accept='image/*'><textarea name='message' placeholder='内容を入力...' rows='10' required></textarea><input type='hidden' name='parent_id' value='-1'><button type='submit' class='btn-primary'>投稿する</button></form></div></div>"
end

get '/robots.txt' do
  content_type 'text/plain'
  "User-agent: *\nAllow: /"
end