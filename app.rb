require 'sinatra'
require 'pg'
require 'time'
require 'bcrypt'
require 'uri'
require 'cgi'

set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'
use Rack::Session::Cookie, :key => 'rack.session', :path => '/', :secret => 'katabami_pharmashare_secret_2026'

def db_connection
  uri = URI.parse(ENV['DATABASE_URL'] || 'postgres://localhost/pharmashare')
  PG.connect(host: uri.host, port: uri.port, dbname: uri.path[1..-1], user: uri.user, password: uri.password)
end

def setup_db
  conn = db_connection
  conn.exec "CREATE TABLE IF NOT EXISTS posts (id SERIAL PRIMARY KEY, user_name TEXT, drug_name TEXT, likes INTEGER DEFAULT 0, stars INTEGER DEFAULT 0, message TEXT, parent_id INTEGER DEFAULT -1, created_at TEXT, title TEXT, image_path TEXT, category TEXT);"
  conn.exec "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, user_name TEXT UNIQUE, password_digest TEXT, email TEXT, bio TEXT, icon_path TEXT);"
  conn.exec "CREATE TABLE IF NOT EXISTS likes_map (id SERIAL PRIMARY KEY, user_name TEXT, post_id INTEGER);"
  conn.exec "CREATE TABLE IF NOT EXISTS stars_map (id SERIAL PRIMARY KEY, user_name TEXT, post_id INTEGER);"
  begin; conn.exec "ALTER TABLE users ADD COLUMN bio TEXT; ALTER TABLE users ADD COLUMN icon_path TEXT;"; rescue; end
  conn.close
end
setup_db

def query(sql, params = [])
  conn = db_connection
  res = conn.exec_params(sql, params)
  yield res if block_given?
ensure; conn.close if conn; end

CATEGORIES = { "インシデントレポート"=>"#ff3b30", "疑義紹介、処方介入事例"=>"#0071e3", "適正使用するためのメモ"=>"#64d2ff", "他職種連携事例"=>"#5856d6", "往診同行"=>"#32d74b", "保険関連"=>"#ff9f0a", "部下後輩教育"=>"#af52de", "その他独り言"=>"#8e8e93" }

def header_menu
  u = session[:user]
  nav = u ? "<a href='/post_new' class='nav-link'>✍️ 投稿</a> <a href='/profile/#{u}' class='nav-link'>👤 マイページ</a> <a href='/logout' class='nav-link'>解除</a>" : "<a href='/login_page' class='nav-link'>ログイン</a>"
  flash = session.delete(:notice) ? "<div class='flash'>#{session[:notice]}</div>" : ""
  "<!DOCTYPE html><html lang='ja'><head><meta charset='UTF-8'><title>PharmaShare</title><style>
    :root { --p: #0071e3; --bg: #f5f5f7; }
    body { font-family: sans-serif; background: var(--bg); margin: 0; }
    nav { background: white; padding: 15px; display: flex; justify-content: space-between; border-bottom: 1px solid #ddd; }
    .container { max-width: 700px; margin: 0 auto; padding: 20px; }
    .card { background: white; padding: 20px; border-radius: 12px; margin-bottom: 15px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    .tag { padding: 4px 8px; border-radius: 4px; color: white; font-size: 0.7rem; text-decoration: none; }
    .nav-link { margin-left: 10px; text-decoration: none; color: #333; }
    .btn { background: var(--p); color: white; border: none; padding: 10px 15px; border-radius: 8px; cursor: pointer; }
    input, textarea, select { width: 100%; padding: 10px; margin: 5px 0; border: 1px solid #ccc; border-radius: 6px; }
    .flash { background: #32d74b; color: white; text-align: center; padding: 10px; }
  </style></head><body><nav><a href='/' style='font-weight:bold; color:var(--p); text-decoration:none;'>PharmaShare</a><div>#{nav}</div></nav>#{flash}<div class='container'>"
end

get '/' do
  word, cat = params[:search], params[:category]
  opts = CATEGORIES.map{|k,v| "<option value='#{k}' #{'selected' if cat==k}>#{k}</option>"}.join
  html = header_menu + "<h1>最新の知恵</h1><form class='card'><input type='text' name='search' placeholder='検索...' value='#{CGI.escapeHTML(word.to_s)}'><select name='category'><option value=''>全カテゴリ</option>#{opts}</select><button class='btn'>検索</button></form>"
  sql = "SELECT * FROM posts WHERE parent_id = -1"
  pams = []
  if word && word != ""; sql += " AND (title LIKE $1 OR message LIKE $1)"; pams << "%#{word}%"; end
  if cat && cat != ""; sql += " AND category = $#{pams.size + 1}"; pams << cat; end
  query(sql + " ORDER BY id DESC", pams) do |res|
    res.each do |r|
      c = r['category'] || "その他独り言"
      html += "<div class='card'><a href='/?category=#{CGI.escape(c)}' class='tag' style='background:#{CATEGORIES[c]}'>#{c}</a><h3 style='margin:10px 0;'><a href='/post/#{r['id']}' style='text-decoration:none; color:#333;'>#{CGI.escapeHTML(r['title'])}</a></h3><small>👨‍⚕️ <a href='/profile/#{r['user_name']}'>#{r['user_name']}</a> | 📅 #{r['created_at']}</small></div>"
    end
  end
  html + "</div></body></html>"
end

get '/post/:id' do
  query("SELECT * FROM posts WHERE id = $1", [params[:id]]) do |res|
    p = res.first; return redirect '/' unless p
    liked = false; query("SELECT 1 FROM likes_map WHERE user_name=$1 AND post_id=$2", [session[:user], p['id']]){|r| liked = r.any?}
    html = header_menu + "<div class='card'><span class='tag' style='background:#{CATEGORIES[p['category']]}'>#{p['category']}</span><h1>#{CGI.escapeHTML(p['title'])}</h1><p>薬剤: #{p['drug_name']}</p><div style='white-space:pre-wrap;'>#{CGI.escapeHTML(p['message'])}</div>"
    if p['image_path'] && p['image_path'] != ""; html += "<img src='/uploads/#{p['image_path']}' style='width:100%; margin-top:10px;'>"; end
    html += "<form action='/post/#{p['id']}/like' method='post' style='margin-top:15px;'><button class='btn' style='background:#{liked ? '#888':'#0071e3'}'>👍 #{p['likes']}</button></form></div>"
    html += "<h3>💬 コメント</h3>"
    query("SELECT * FROM posts WHERE parent_id = $1 ORDER BY id ASC", [p['id']]){|rs| rs.each{|r| html += "<div class='card' style='margin-left:20px;'><small>#{r['user_name']}</small><p>#{CGI.escapeHTML(r['message'])}</p></div>"}}
    html + "</div>"
  end
end

get '/profile/:name' do
  u = nil; query("SELECT * FROM users WHERE user_name = $1", [params[:name]]){|res| u = res.first}
  return header_menu + "ユーザー不在</div>" unless u
  icon = (u['icon_path'] && u['icon_path']!="") ? "/uploads/#{u['icon_path']}" : "https://ui-avatars.com/api/?name=#{u['user_name']}"
  html = header_menu + "<div class='card' style='text-align:center;'><img src='#{icon}' style='width:80px; height:80px; border-radius:50%;'><h2 style='margin:10px 0;'>#{u['user_name']} 先生</h2><p style='text-align:left; background:#f9f9f9; padding:10px; border-radius:8px;'>#{CGI.escapeHTML(u['bio'].to_s)}</p>"
  html += "<a href='/profile_edit' class='btn' style='text-decoration:none;'>編集</a>" if session[:user] == u['user_name']
  html += "</div><h3>投稿一覧</h3>"
  query("SELECT * FROM posts WHERE user_name = $1 AND parent_id = -1 ORDER BY id DESC", [u['user_name']]){|res| res.each{|r| html += "<div class='card'><a href='/post/#{r['id']}'>#{CGI.escapeHTML(r['title'])}</a></div>"}}
  html + "</div>"
end

get '/profile_edit' do
  u = nil; query("SELECT * FROM users WHERE user_name = $1", [session[:user]]){|res| u = res.first}
  header_menu + "<h1>編集</h1><div class='card'><form action='/profile_update' method='post' enctype='multipart/form-data'><label>アイコン</label><input type='file' name='icon'><label>自己紹介</label><textarea name='bio'>#{u['bio']}</textarea><label>メール</label><input type='email' name='email' value='#{u['email']}' required><button class='btn'>保存</button></form></div>"
end

post '/profile_update' do
  redirect '/login_page' unless session[:user]
  f = params[:icon]; fname = f ? "icon_#{Time.now.to_i}_#{f[:filename]}" : nil
  if f; Dir.mkdir("./public/uploads") unless Dir.exist?("./public/uploads"); File.open("./public/uploads/#{fname}", 'wb'){|file| file.write(f[:tempfile].read)}; end
  if fname
    query("UPDATE users SET email=$1, bio=$2, icon_path=$3 WHERE user_name=$4", [params[:email], params[:bio], fname, session[:user]])
  else
    query("UPDATE users SET email=$1, bio=$2 WHERE user_name=$3", [params[:email], params[:bio], session[:user]])
  end
  redirect "/profile/#{session[:user]}"
end

get '/post_new' do
  ops = CATEGORIES.map{|k,v| "<option value='#{k}'>#{k}</option>"}.join
  header_menu + "<h1>新規投稿</h1><div class='card'><form action='/post' method='post' enctype='multipart/form-data'><select name='category'>#{ops}</select><input type='text' name='title' placeholder='タイトル' required><input type='text' name='drug_name' placeholder='薬剤名'><textarea name='message' placeholder='内容' rows='8'></textarea><input type='file' name='image'><button class='btn'>投稿</button></form></div>"
end

post '/post' do
  img = params[:image]; fname = img ? "#{Time.now.to_i}_#{img[:filename]}" : ""
  if img; Dir.mkdir("./public/uploads") unless Dir.exist?("./public/uploads"); File.open("./public/uploads/#{fname}", 'wb'){|f| f.write(img[:tempfile].read)}; end
  query("INSERT INTO posts (user_name, drug_name, message, title, created_at, parent_id, category, image_path) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)", [session[:user], params[:drug_name], params[:message], params[:title], Time.now.strftime('%Y/%m/%d'), -1, params[:category], fname])
  redirect '/'
end

get '/login_page' do
  header_menu + "<div class='card'><h2>ログイン</h2><form action='/auth' method='post'><input type='text' name='user_name' placeholder='ユーザー名' required><input type='password' name='password' placeholder='パスワード' required><button class='btn'>送信</button></form></div>"
end

post '/auth' do
  u = nil; query("SELECT * FROM users WHERE user_name = $1", [params[:user_name]]){|res| u = res.first}
  if u && BCrypt::Password.new(u['password_digest']) == params[:password]
    session[:user] = u['user_name']; redirect '/'
  elsif !u
    h = BCrypt::Password.create(params[:password])
    query("INSERT INTO users (user_name, password_digest) VALUES ($1, $2)", [params[:user_name], h])
    session[:user] = params[:user_name]; redirect '/'
  else
    session[:notice] = "認証失敗"; redirect '/login_page'
  end
end

get '/logout' do; session.clear; redirect '/'; end

post '/post/:id/like' do
  redirect '/login_page' unless session[:user]
  query("SELECT 1 FROM likes_map WHERE user_name=$1 AND post_id=$2", [session[:user], params[:id]]) do |res|
    if res.any?
      query("DELETE FROM likes_map WHERE user_name=$1 AND post_id=$2", [session[:user], params[:id]])
      query("UPDATE posts SET likes = likes - 1 WHERE id=$1", [params[:id]])
    else
      query("INSERT INTO likes_map (user_name, post_id) VALUES ($1, $2)", [session[:user], params[:id]])
      query("UPDATE posts SET likes = likes + 1 WHERE id=$1", [params[:id]])
    end
  end
  redirect back
end

get '/robots.txt' do; content_type 'text/plain'; "User-agent: *\nAllow: /"; end