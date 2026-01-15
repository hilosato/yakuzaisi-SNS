require 'sinatra'
require 'pg'
require 'time'
require 'bcrypt'
require 'uri'
require 'cgi'

# --- サーバー設定 ---
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

# セッション設定（Renderの最新Ruby 3.4対応の長いキー）
use Rack::Session::Cookie, :key => 'rack.session',
                           :path => '/',
                           :secret => 'katabami_pharmashare_2026_super_long_secret_key_for_security_reason_over_64_characters'

# --- データベース接続設定 ---
def db_connection
  db_url = ENV['DATABASE_URL']
  uri = URI.parse(db_url || 'postgres://localhost/pharmashare')
  PG.connect(host: uri.host, port: uri.port, dbname: uri.path[1..-1], user: uri.user, password: uri.password)
end

# テーブル作成
def setup_db
  conn = db_connection
  conn.exec "CREATE TABLE IF NOT EXISTS posts (id SERIAL PRIMARY KEY, user_name TEXT, drug_name TEXT, likes INTEGER DEFAULT 0, message TEXT, parent_id INTEGER DEFAULT -1, created_at TEXT, title TEXT, category TEXT);"
  conn.exec "CREATE TABLE IF NOT EXISTS users (id SERIAL PRIMARY KEY, user_name TEXT UNIQUE, password_digest TEXT, email TEXT);"
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

# --- ヘルパーメソッド（検索ハイライト） ---
def highlight(text, word)
  return CGI.escapeHTML(text) if word.nil? || word.empty?
  escaped_text = CGI.escapeHTML(text)
  escaped_word = CGI.escapeHTML(word)
  escaped_text.gsub(/(#{Regexp.escape(escaped_word)})/i, '<mark style="background-color: #ffef00; color: black; padding: 0 2px; border-radius: 4px;">\1</mark>')
end

# --- デザイン共通パーツ ---
def header_menu
  user_status = if session[:user]
    "<a href='/post_new' class='nav-link'>✍️ 投稿</a> <a href='/logout' class='nav-link'>ログアウト</a>"
  else
    "<a href='/login_page' class='nav-link'>ログイン / 登録</a>"
  end
  "
  <!DOCTYPE html>
  <html lang='ja'>
  <head>
    <meta charset='UTF-8'>
    <title>PharmaShare</title>
    <style>
      :root { --primary: #0071e3; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; }
      body { font-family: -apple-system, sans-serif; margin: 0; background: var(--bg); color: var(--text); }
      .container { max-width: 600px; margin: 0 auto; padding: 20px; }
      nav { background: white; padding: 15px 20px; display: flex; justify-content: space-between; border-bottom: 1px solid #ddd; }
      .nav-brand { font-weight: bold; color: var(--primary); text-decoration: none; }
      .nav-link { color: var(--text); text-decoration: none; margin-left: 15px; font-size: 0.9rem; }
      .post-card { background: var(--card); padding: 20px; border-radius: 12px; margin-bottom: 15px; box-shadow: 0 2px 5px rgba(0,0,0,0.05); }
      .btn-primary { background: var(--primary); color: white; border: none; padding: 10px 20px; border-radius: 8px; cursor: pointer; }
      input, textarea { width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
    </style>
  </head>
  <body>
    <nav><a href='/' class='nav-brand'>PharmaShare</a><div>#{user_status}</div></nav>
    <div class='container'>
  "
end

# --- ルート設定 ---

# ホーム画面
get '/' do
  word = params[:search]
  html = header_menu + "<h1>知恵の共有</h1>"
  html += "<form action='/' method='get' class='post-card'><input type='text' name='search' placeholder='キーワード検索...' value='#{CGI.escapeHTML(word.to_s)}'><button class='btn-primary'>検索</button></form>"
  
  sql = "SELECT * FROM posts WHERE parent_id = -1 "
  sql_params = []
  if word && word != ""
    sql += "AND (title LIKE $1 OR drug_name LIKE $1 OR message LIKE $1) "
    sql_params << "%#{word}%"
  end
  sql += "ORDER BY id DESC"

  query(sql, sql_params) do |res|
    res.each do |row|
      html += "<div class='post-card'>
                <small style='color:#888;'>💊 #{highlight(row['drug_name'], word)}</small>
                <h3><a href='/post/#{row['id']}' style='text-decoration:none; color:var(--text);'>#{highlight(row['title'], word)}</a></h3>
                <p style='font-size:0.9rem;'>#{row['user_name']} 先生 | #{row['created_at']}</p>
              </div>"
    end
  end
  html + "</div></body></html>"
end

# 投稿詳細
get '/post/:id' do
  query("SELECT * FROM posts WHERE id = $1", [params[:id]]) do |res|
    post = res.first
    return "投稿が見つかりません" unless post
    header_menu + "<div class='post-card'><h1>#{CGI.escapeHTML(post['title'])}</h1><p>薬剤: #{CGI.escapeHTML(post['drug_name'])}</p><hr><p>#{CGI.escapeHTML(post['message'])}</p><a href='/'>← 戻る</a></div></div>"
  end
end

# 新規投稿ページ
get '/post_new' do
  redirect '/login_page' unless session[:user]
  header_menu + "<h1>新規投稿</h1><div class='post-card'><form action='/post' method='post'><input type='text' name='title' placeholder='タイトル' required><input type='text' name='drug_name' placeholder='薬剤名'><textarea name='message' placeholder='内容' rows='5' required></textarea><button class='btn-primary'>投稿する</button></form></div></div>"
end

# 投稿処理
post '/post' do
  redirect '/login_page' unless session[:user]
  jst_time = Time.now.getlocal('+09:00').strftime('%Y/%m/%d %H:%M')
  query("INSERT INTO posts (user_name, drug_name, message, title, created_at) VALUES ($1, $2, $3, $4, $5)", 
         [session[:user], params[:drug_name], params[:message], params[:title], jst_time])
  redirect '/'
end

# ログイン・登録
get '/login_page' do
  header_menu + "<div class='post-card'><h2>ログイン / 新規登録</h2><form action='/auth' method='post'><input type='text' name='user_name' placeholder='ユーザー名' required><input type='password' name='password' placeholder='パスワード' required><button class='btn-primary' style='width:100%'>送信</button></form></div></div>"
end

post '/auth' do
  user = nil
  query("SELECT * FROM users WHERE user_name = $1", [params[:user_name]]) { |res| user = res.first }
  if user
    if BCrypt::Password.new(user['password_digest']) == params[:password]
      session[:user] = user['user_name']
      redirect '/'
    else
      "パスワードが違います"
    end
  else
    hash_pass = BCrypt::Password.create(params[:password])
    query("INSERT INTO users (user_name, password_digest) VALUES ($1, $2)", [params[:user_name], hash_pass])
    session[:user] = params[:user_name]
    redirect '/'
  end
end

get '/logout' do
  session.clear
  redirect '/'
end