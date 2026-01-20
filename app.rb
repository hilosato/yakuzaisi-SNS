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
  conn.exec "ALTER TABLE users ADD COLUMN IF NOT EXISTS icon_path TEXT;"

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
  "【至急】誰か教えて！" => "#af52de",
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

# アイコンを表示するためのHTMLを生成するヘルパー
def user_icon(u_name, i_path, size=50)
  font_size = (size * 0.4).to_i
  if i_path && i_path != ""
    # 画像がある場合：object-fit:coverで、どんな縦横比の画像も綺麗に丸く切り抜くよ
    "<img src='/uploads/#{i_path}' style='width:#{size}px; height:#{size}px; border-radius:50%; object-fit:cover; border:1px solid #eee;'>"
  else
    # 画像がない場合は一文字目
    "<div style='width:#{size}px; height:#{size}px; background:var(--primary); color:white; border-radius:50%; display:flex; align-items:center; justify-content:center; font-size:#{font_size}px; font-weight:700;'>#{u_name[0]}</div>"
  end
end

# --- デザイン共通パーツ ---
def header_menu(page_title = nil) # (1) 引数 (page_title = nil) を追加！
  # (2) タイトルがあれば「タイトル | PharmaShare」、なければデフォルトを表示
  full_title = page_title ? "#{page_title} | PharmaShare" : "PharmaShare - 薬剤師専用SNS｜現場の知恵と経験が集まる場所"
  
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


    <title>#{full_title}</title> <meta name='description' content='インシデント事例、疑義紹介、他職種連携から部下教育まで。教科書には載っていない「日常の忙しさに埋もれてしまう貴重な気づきと経験」を共有する薬剤師専用SNS。日々の業務に直結する知恵を、発信して共有しよう。'>
    <style>
      :root { --primary: #0071e3; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --secondary: #86868b; --accent: #32d74b; --star: #ff9f0a; }
      body { font-family: -apple-system, sans-serif; margin: 0; background: var(--bg); color: var(--text); line-height: 1.6; font-size: 24px; }
      .container { max-width: 1000px; margin: 0 auto; padding: 40px 20px; }
      nav { 
        background: rgba(255, 255, 255, 0.8); 
        backdrop-filter: blur(20px); 
        padding: 25px 20px; /* 10pxから25pxに増やして、上下をガッツリ太くしたよ！ */
        display: flex; 
        justify-content: center; 
        border-bottom: 2px solid rgba(0,0,0,0.1); /* 境界線も少しハッキリ */
        position: sticky; 
        top: 0; 
        z-index: 100; 
      }

      /* ロゴ周り：さらにドカンと大きく */
      .nav-brand { 
        font-weight: 800; 
        color: var(--primary); 
        font-size: 2.8rem; /* 2.2remから2.8remにアップ！ */
        letter-spacing: -1px; 
      }
      
      .nav-subtitle { 
        font-size: 1.4rem; /* サブタイトルも存在感アップ */
        color: var(--secondary); 
        font-weight: 600; 
      }

      /* 右側のメニューボタンも大きく */
      .nav-link { 
        color: var(--text); 
        text-decoration: none; 
        font-size: 28px; /* 24pxから28pxにアップ！ */
        margin-left: 25px; 
        font-weight: 700; 
      }
      .nav-inner {
        width: 100%;
        max-width: 1000px;
        display: flex;
        justify-content: space-between;
        align-items: center;
      }


      /* 左上のロゴを大きくするデザイン */
      .nav-brand-group { display: flex; align-items: baseline; gap: 12px; text-decoration: none; }
      .nav-brand { font-weight: 800; color: var(--primary); font-size: 2.2rem; letter-spacing: -0.5px; }
      .nav-subtitle { font-size: 1.2rem; color: var(--secondary); font-weight: 600; }
      
      .nav-link { color: var(--text); text-decoration: none; font-size: 24px; margin-left: 15px; font-weight: 500; }
      .post-card { background: var(--card); padding: 30px; border-radius: 18px; margin-bottom: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); }
      .tag { padding: 6px 12px; border-radius: 8px; font-size: 20px; font-weight: 700; color: white; margin-right: 8px; }
      .btn-primary { background: var(--primary); color: white; border: none; padding: 18px 30px; border-radius: 12px; font-weight: 600; cursor: pointer; font-size: 24px; }
      input, textarea, select { width: 100%; padding: 18px; margin: 10px 0; border: 1px solid #d2d2d7; border-radius: 12px; box-sizing: border-box; font-size: 24px !important; }
      .flash-notice { 
       background: #ff3b30; /* 警告の赤色 */
       color: white; 
       padding: 25px; 
       text-align: center; 
       font-weight: 800; 
       font-size: 28px; /* 文字を大きく */
       border-bottom: 4px solid #d70015; /* 下線でさらに強調 */
       box-shadow: 0 4px 10px rgba(0,0,0,0.1);
      }


      .stat-num { font-size: 2.5rem; font-weight: 800; color: var(--primary); display: block; line-height: 1; margin-bottom: 5px; }
      .stat-label { font-size: 24px; color: var(--secondary); font-weight: 600; }
      .stat-box { flex: 1; text-align: center; background: #f0f7ff; padding: 20px; border-radius: 16px; }

  h1 { font-size: 42px; margin-bottom: 30px; }
  h3 { font-size: 32px; }
  h4 { font-size: 28px; }


/* --- スマホ（画面幅が768px以下）の時だけ適用される設定 --- */
  @media (max-width: 768px) {
    /* スマホでは文字をさらに大きく！ */
    .nav-brand { font-size: 3.2rem !important; }
    .nav-subtitle { font-size: 1.6rem !important; }
    .nav-link { font-size: 32px !important; margin-left: 15px; }
    
    /* 投稿内容などもスマホではさらに読みやすく */
    body { font-size: 28px; }
    .btn-primary { font-size: 30px; padding: 20px; }
    
    /* スマホで横並びがキツい場合は縦に並べる（必要に応じて） */
    .nav-inner {
      flex-direction: column; /* ロゴとメニューを上下に分ける */
      gap: 10px;
    }
  }


      </style>
  </head>
<body>
    <nav>
      <div class='nav-inner'> 
        <a href='/' class='nav-brand-group'>
          <span class='nav-brand'>PharmaShare</span>
          <span class='nav-subtitle'>薬剤師専用SNS</span>
        </a>
        <div class='nav-links'>
          <a href='/' class='nav-link'>🏠 ホーム</a>
          #{user_status}
        </div>
      </div> 
    </nav>
    #{flash_msg}
    <div class='container'>
  "
end

# --- ホーム画面 ---
get '/' do
  word = params[:search]
selected_cat = params[:category]

# この1行を追加（タイトルの準備）
title = word && word != "" ? "「#{word}」の検索結果" : nil

# header_menu(title) に書き換え
html = header_menu(title) + "<h1>みんなの投稿一覧</h1>"
  
  # カテゴリ選択ボタンの表示
  html += "<div style='margin-bottom: 25px; display: flex; flex-wrap: wrap; gap: 12px;'>"
  html += "<a href='/' style='text-decoration:none; padding: 12px 20px; border-radius: 12px; font-size: 22px; border: 2px solid #ddd; background: #{selected_cat ? 'white' : '#666'}; color: #{selected_cat ? '#666' : 'white'}; font-weight: bold;'>すべて</a>"
  CATEGORIES.each do |name, color|
    is_active = (selected_cat == name)
    bg_color = is_active ? color : "white"
    text_color = is_active ? "white" : color # 未選択時は枠線の色と同じにして視認性アップ
    html += "<a href='/?category=#{CGI.escape(name)}' style='text-decoration:none; padding: 12px 20px; border-radius: 12px; font-size: 22px; border: 2px solid #{color}; background: #{bg_color}; color: #{text_color}; font-weight: bold;'>#{name}</a>"
  end
  html += "</div>"
　
# --- 創設者メッセージへのリンクを追加 ---
  html += "
    <div style='margin: 10px 0 30px 0; text-align: right;'>
      <a href='/about' style='text-decoration: none; font-size: 24px; color: var(--primary); font-weight: 800; display: inline-flex; align-items: center; justify-content: flex-end; gap: 10px; padding: 10px 20px; background: #fff; border-radius: 15px; border: 2px solid #eef6ff; box-shadow: 0 4px 10px rgba(0,0,0,0.03);'>
        <span style='background: var(--primary); color: white; border-radius: 50%; width: 40px; height: 40px; display: flex; align-items: center; justify-content: center; font-size: 24px;'>💡</span>
        <span>PharmaShareとは？（創設者のメッセージ）</span>
      </a>
    </div>
  "


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
      <div class='post-card' style='padding: 25px;'>
        <div style='display:flex; justify-content:space-between; align-items:flex-start;'>
          <div style='flex: 1;'>
            <div style='margin-bottom: 12px;'>
              <span class='tag' style='background:#{CATEGORIES[cat_name] || '#8e8e93'};'>#{cat_name}</span>
            </div>
            <div style='color:var(--secondary); font-size: 24px; font-weight: 700; margin-bottom: 10px;'>
              💊 #{display_drug}
            </div>
            <h3 style='margin:10px 0; font-size: 30px;'><a href='/post/#{row['id']}' style='text-decoration:none; color:var(--text);'>#{display_title}</a></h3>
            <p style='color:var(--secondary); font-size: 20px; margin: 10px 0 0 0;'>
              👨‍⚕️ <a href='/profile/#{row['user_name']}' style='text-decoration:none; color:var(--primary); font-weight:600;'>#{row['user_name']}</a> | 📅 #{row['created_at'].split(' ')[0]}
            </p>
          </div>
          <div style='text-align:right; margin-left:20px; min-width: 100px;'>
            <div style='font-size: 32px; font-weight: 800; color: var(--primary); margin-bottom: 10px;'>👍 #{row['likes']}</div>
            <div style='font-size: 32px; font-weight: 800; color: var(--star);'>⭐️ #{row['stars']}</div>
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
    return header_menu("投稿が見つかりませんでした") + "<div class='container'><h1>投稿が見つかりませんでした。</h1></div>" unless post
    
    replies = []
    query("SELECT * FROM posts WHERE parent_id = $1 ORDER BY id ASC", [params[:id]]) { |r_res| replies = r_res.to_a }
    
    is_liked = false
    is_starred = false
    query("SELECT id FROM likes_map WHERE user_name = $1 AND post_id = $2", [session[:user], post['id']]) { |r| is_liked = true if r.any? }
    query("SELECT id FROM stars_map WHERE user_name = $1 AND post_id = $2", [session[:user], post['id']]) { |r| is_starred = true if r.any? }
    
    # ボタンの状態（アクティブなら色を変える）
    l_class = is_liked ? "action-btn like-btn active" : "action-btn like-btn"
    s_class = is_starred ? "action-btn star-btn active" : "action-btn star-btn"
    
    html = header_menu(post['title']) + "
    <div class='container' style='max-width: 1000px;'>
      <a href='/' style='text-decoration:none; color:var(--primary); font-weight:800; font-size: 26px;'>← 戻る</a>
      
      <div class='post-card' style='margin-top:30px; padding: 40px;'>
        <div style='display:flex; justify-content:space-between; align-items:center; margin-bottom: 20px;'>
          <span class='tag' style='background:#{CATEGORIES[post['category']] || '#8e8e93'}; font-size: 22px; padding: 8px 20px;'>#{post['category']}</span>
          #{post['user_name'] == session[:user] ? "<a href='/post/#{post['id']}/edit' style='font-size: 22px; color:var(--primary); text-decoration:none; font-weight: 800;'>✏️ 編集する</a>" : ""}
        </div>

        <div style='color:var(--secondary); font-size: 26px; font-weight: 700; margin-bottom: 15px;'>
          💊 #{CGI.escapeHTML(post['drug_name'].to_s)}
        </div>

        <h1 style='margin:10px 0; font-size: 42px; line-height: 1.3;'>#{CGI.escapeHTML(post['title'])}</h1>
        <p style='color:var(--secondary); font-size: 22px; margin-bottom: 30px;'>投稿者: #{post['user_name']} 先生</p>
        
        <hr style='border:0; border-top:2px solid #eee; margin:30px 0;'>

        #{ (post['image_path'] && post['image_path'] != "") ? "<div style='margin-bottom:30px;'><img src='/uploads/#{post['image_path']}' style='width:100%; border-radius:15px; border:1px solid #ddd;'></div>" : "" }

        <div style='white-space: pre-wrap; font-size: 28px; line-height: 1.8; color: var(--text);'>#{CGI.escapeHTML(post['message'])}</div>

        <div style='display:flex; gap:20px; margin-top:40px;'>
          <form action='/post/#{post['id']}/like' method='post' style='flex:1;'>
            <button type='submit' class='#{l_class}' style='width:100%; height:80px; font-size: 26px; font-weight: 800;'>👍 役に立った！ (#{post['likes']})</button>
          </form>
          <form action='/post/#{post['id']}/star' method='post' style='flex:1;'>
            <button type='submit' class='#{s_class}' style='width:100%; height:80px; font-size: 26px; font-weight: 800;'>⭐️ お気に入り (#{post['stars']})</button>
          </form>
        </div>
        
        #{post['user_name'] == session[:user] ? "
          <form action='/post/#{post['id']}/delete' method='post' style='margin-top:30px; text-align: right;' onsubmit='return confirm(\"本当に削除しますか？\");'>
            <button type='submit' style='background:none; border:none; color:#ff3b30; cursor:pointer; font-size: 22px; font-weight: 600;'>🗑️ この投稿を削除する</button>
          </form>" : ""
        }

        <div class='reply-form' style='margin-top:50px; padding-top:40px; border-top:2px solid #eee;'>
          <h4 style='font-size: 32px; margin-bottom: 25px;'>💬 コメント・返信</h4>
          <form action='/post' method='post' enctype='multipart/form-data'>
            <input type='hidden' name='parent_id' value='#{post['id']}'>
            <input type='hidden' name='category' value='#{post['category']}'>
            <input type='hidden' name='drug_name' value='#{post['drug_name']}'>
            <input type='hidden' name='title' value='Re: #{post['title']}'>
            
            <textarea name='message' placeholder='返信を入力...' required style='font-size: 26px !important; padding: 20px; border: 2px solid #d2d2d7; width: 100%; border-radius: 12px; margin-bottom: 20px;' rows='4'></textarea>
            
            <div style='margin-bottom: 25px;'>
              <label style='display:block; font-size: 20px; color: var(--secondary); margin-bottom: 10px;'>📸 画像を添付（任意）</label>
              <input type='file' name='image' accept='image/*' style='font-size: 22px;'>
            </div>
            
            <button type='submit' class='btn-primary' style='width: 100%; height: 90px; font-size: 32px; font-weight: 900;'>返信を送信</button>
          </form>
        </div>
      </div>"
    
    # 返信のループ
    replies.each do |r| 
      html += "
      <div class='post-card' style='margin-left: 40px; background:#fbfbfd; padding: 30px; border-left: 10px solid #eee;'>
        <div style='display:flex; justify-content:space-between; align-items: flex-start; margin-bottom: 15px;'>
          <div>
            <strong style='font-size: 24px;'>#{r['user_name']} 先生</strong> 
            <span style='color:var(--secondary); font-size: 18px; margin-left: 10px;'>#{r['created_at']}</span>
          </div>
          <div style='display:flex; gap:15px;'>"
      if r['user_name'] == session[:user]
        html += "
        <a href='/post/#{r['id']}/edit' style='font-size: 20px; color:var(--primary); text-decoration:none; font-weight: 700;'>編集</a>
        <form action='/post/#{r['id']}/delete' method='post' onsubmit='return confirm(\"この返信を削除しますか？\");'>
          <button type='submit' style='background:none; border:none; color:#ff3b30; cursor:pointer; font-size: 20px; font-weight: 700;'>削除</button>
        </form>"
      end
      html += "
          </div>
        </div>
        <div style='font-size: 26px; line-height: 1.6; white-space: pre-wrap;'>#{CGI.escapeHTML(r['message'])}</div>"
      
      if r['image_path'] && r['image_path'] != ""
        html += "<div style='margin-top:20px;'><img src='/uploads/#{r['image_path']}' style='max-width:100%; border-radius:12px; border:1px solid #ddd;'></div>"
      end
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

# --- 公開プロフィールページ（他の人から見えるページ） ---
get '/profile/:user_name' do
  viewing_user = params[:user_name]
  
  user_data, post_count, total_likes, total_stars = nil, 0, 0, 0
  query("SELECT * FROM users WHERE user_name = $1", [viewing_user]) { |res| user_data = res.first if res.any? }
  
  if user_data.nil?
    return header_menu("エラー") + "<div class='container'><h1>ユーザーが見つかりません</h1></div>"
  end

  query("SELECT COUNT(*) FROM posts WHERE user_name = $1 AND parent_id = -1", [viewing_user]) { |res| post_count = res.first['count'] }
  query("SELECT SUM(likes) as l, SUM(stars) as s FROM posts WHERE user_name = $1", [viewing_user]) do |res| 
    total_likes = res.first['l'] || 0
    total_stars = res.first['s'] || 0
  end

  is_mine = (session[:user] == viewing_user)

  # ワイド幅1000pxのコンテナで包む
  html = header_menu("#{viewing_user}先生") + "
    <div class='container' style='max-width: 1000px;'>
      <h1 style='text-align:center; font-size: 42px; margin-bottom: 30px;'>#{viewing_user} 先生</h1>
      
      <div class='post-card' style='padding: 40px;'>
        <div style='text-align:center; margin-bottom:30px;'>
          <div style='display:flex; justify-content:center; margin-bottom:20px;'>
            #{user_icon(viewing_user, user_data['icon_path'], 120)} </div>
          
          <div style='font-size: 28px; color: var(--text); white-space: pre-wrap; padding: 30px; background: #f9f9fb; border-radius: 20px; border: 2px solid #eee; text-align: left; line-height: 1.6;'>
            <label style='display: block; font-size: 22px; color: var(--secondary); font-weight: 800; margin-bottom: 10px;'>📝 自己紹介</label>
            #{CGI.escapeHTML(user_data['bio'].to_s == '' ? '自己紹介はまだありません。' : user_data['bio'])}
          </div>
        </div>

        <div style='display:flex; gap:20px;'>
          <div class='stat-box' style='padding: 25px; flex: 1;'><span class='stat-num' style='font-size: 3.5rem;'>#{post_count}</span><span class='stat-label' style='font-size: 24px;'>投稿数</span></div>
          <div class='stat-box' style='padding: 25px; flex: 1;'><span class='stat-num' style='font-size: 3.5rem;'>#{total_likes}</span><span class='stat-label' style='font-size: 24px;'>もらった👍</span></div>
          <div class='stat-box' style='padding: 25px; flex: 1;'><span class='stat-num' style='font-size: 3.5rem;'>#{total_stars}</span><span class='stat-label' style='font-size: 24px;'>もらった⭐️</span></div>
        </div>
      </div>

      <h2 style='font-size: 36px; margin: 40px 0 20px 10px;'>📝 最近の投稿</h2>
  "
  
  query("SELECT * FROM posts WHERE user_name = $1 AND parent_id = -1 ORDER BY id DESC LIMIT 5", [viewing_user]) do |res|
    res.each do |row|
      html += "
      <div class='post-card' style='padding: 30px; margin-bottom: 20px;'>
        <h3 style='font-size: 30px; margin-bottom: 10px;'>
          <a href='/post/#{row['id']}' style='text-decoration:none; color:var(--text); font-weight:800;'>#{CGI.escapeHTML(row['title'])}</a>
        </h3>
        <div style='color:var(--secondary); font-size: 22px;'>💊 #{CGI.escapeHTML(row['drug_name'])} | 📅 #{row['created_at'].split(' ')[0]}</div>
      </div>"
    end
  end

  # 自分のページなら管理画面へのリンク、そうでなければタイムラインへのリンク
  if is_mine
    html += "<div style='text-align:center; margin-top:40px;'><a href='/profile' class='btn-primary' style='text-decoration:none; height: 80px; display: flex; align-items: center; justify-content: center; font-size: 28px; font-weight: 800;'>自分の管理画面へ戻る</a></div>"
  else
    html += "<div style='text-align:center; margin-top:40px;'><a href='/' style='font-size: 26px; color: var(--primary); text-decoration: none; font-weight: 700;'>← タイムラインに戻る</a></div>"
  end

  html + "</div>"
end

# --- マイページ（プロフィール） ---
get '/profile' do
  redirect '/login_page' unless session[:user]
  
  current_email, current_bio, current_icon, post_count, total_likes, total_stars = "", "", nil, 0, 0, 0
  # ユーザー情報の取得
  query("SELECT email, bio, icon_path FROM users WHERE user_name = $1", [session[:user]]) do |res| 
    if res.any?
      current_email = res.first['email']
      current_bio = res.first['bio']
      current_icon = res.first['icon_path'] 
    end
  end
  # 統計情報の取得
  query("SELECT COUNT(*) FROM posts WHERE user_name = $1 AND parent_id = -1", [session[:user]]) { |res| post_count = res.first['count'] }
  query("SELECT SUM(likes) as l, SUM(stars) as s FROM posts WHERE user_name = $1", [session[:user]]) do |res| 
    total_likes = res.first['l'] || 0
    total_stars = res.first['s'] || 0
  end

  # ヘッダーに「マイページ」とタイトルを表示
  html = header_menu("マイページ") + "
    <div class='container' style='max-width: 1000px;'> <h1 style='font-size: 42px; margin-bottom: 30px;'>👤 マイページ</h1>
      
      <div class='post-card' style='padding: 40px;'>
        <div style='text-align:center; margin-bottom: 30px;'>
          <div style='display:flex; justify-content:center; margin-bottom:20px;'>
            #{user_icon(session[:user], current_icon, 120)} </div>
          <h3 style='margin:0; font-size: 38px;'>#{session[:user]} 先生</h3>
          
          <div style='margin-top: 25px;'>
            <a href='/profile/#{session[:user]}' style='display: inline-block; padding: 15px 35px; background: #eef6ff; color: var(--primary); text-decoration: none; border-radius: 40px; font-size: 26px; font-weight: 800; border: 3px solid var(--primary);'>
              🔍 公開プロフィールを確認する
            </a>
          </div>
        </div>

        <div style='background: #f9f9fb; padding: 30px; border-radius: 20px; border: 2px solid #eee; margin-bottom: 30px;'>
          <label style='display: block; font-size: 22px; color: var(--secondary); font-weight: 800; margin-bottom: 15px;'>現在の自己紹介</label>
          <div style='font-size: 28px; color: var(--text); white-space: pre-wrap; line-height: 1.6;'>#{CGI.escapeHTML(current_bio.to_s == '' ? '自己紹介はまだありません。' : current_bio)}</div>
        </div>

        <div style='display:flex; gap:20px;'>
          <div class='stat-box' style='padding: 25px; flex: 1;'><span class='stat-num' style='font-size: 3.5rem;'>#{post_count}</span><span class='stat-label' style='font-size: 24px;'>投稿数</span></div>
          <div class='stat-box' style='padding: 25px; flex: 1;'><span class='stat-num' style='font-size: 3.5rem;'>#{total_likes}</span><span class='stat-label' style='font-size: 24px;'>もらった👍</span></div>
          <div class='stat-box' style='padding: 25px; flex: 1;'><span class='stat-num' style='font-size: 3.5rem;'>#{total_stars}</span><span class='stat-label' style='font-size: 24px;'>もらった⭐️</span></div>
        </div>
      </div>

      <div class='post-card' style='display: flex; flex-direction: column; gap: 20px; padding: 40px;'>
        <h4 style='font-size: 32px; margin: 0;'>🔍 コンテンツを確認する</h4>
        <a href='/my_posts' class='btn-primary' style='text-decoration: none; text-align: center; background: #3498db; height: 85px; display: flex; align-items: center; justify-content: center; font-size: 30px; font-weight: 800;'>📝 自分の投稿一覧</a>
        <a href='/my_favorites' class='btn-primary' style='text-decoration: none; text-align: center; background: var(--star); height: 85px; display: flex; align-items: center; justify-content: center; font-size: 30px; font-weight: 800;'>⭐️ お気に入りした投稿</a>
      </div>

      <div class='post-card' style='padding: 40px;'>
        <h4 style='font-size: 32px; margin-bottom: 30px;'>👤 プロフィール編集</h4>
        <form action='/update_profile' method='post' enctype='multipart/form-data'>
          
          <div style='margin-bottom: 30px;'>
            <label style='font-size: 24px; font-weight: 800; color: var(--secondary); display: block; margin-bottom: 10px;'>プロフィールアイコン</label>
            <input type='file' name='icon_image' accept='image/*' style='font-size: 26px; width: 100%;'>
          </div>

          <div style='margin-bottom: 30px;'>
            <label style='font-size: 24px; font-weight: 800; color: var(--secondary); display: block; margin-bottom: 10px;'>自己紹介（キャリアや得意分野など）</label>
            <textarea name='bio' placeholder='例：門前で5年勤務しています。漢方が得意です。' rows='4' style='font-size: 28px !important; padding: 20px; border: 2px solid #d2d2d7; width: 100%; border-radius: 12px; line-height: 1.5;'>#{current_bio}</textarea>
          </div>
          
          <div style='margin-bottom: 35px;'>
            <label style='font-size: 24px; font-weight: 800; color: var(--secondary); display: block; margin-bottom: 10px;'>メールアドレス（投稿に必須）</label>
            <input type='email' name='email' value='#{current_email}' placeholder='example@mail.com' required style='height: 85px; font-size: 30px !important; width: 100%; border-radius: 12px; border: 2px solid #d2d2d7; padding: 0 15px;'>
          </div>
          
          <button type='submit' class='btn-primary' style='width: 100%; height: 100px; font-size: 34px; font-weight: 900; border-radius: 18px;'>プロフィールを保存</button>
        </form>
        
        <div style='margin-top: 50px; text-align: center; border-top: 2px solid #eee; padding-top: 30px;'>
          <a href='/logout' style='color: #e74c3c; font-size: 28px; font-weight: 900; text-decoration: none;'>🚪 ログアウト</a>
        </div>
      </div>
    </div>
  "
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

# --- 創設者からのメッセージ（紹介ページ） ---
get '/about' do
  html = header_menu("創設者の想い") + "
    <div class='container' style='max-width: 1000px;'>
      <div class='post-card' style='padding: 60px; line-height: 1.8;'>
        <h1 style='font-size: 48px; color: var(--primary); text-align: center; margin-bottom: 50px;'>💡 PharmaShare に込めた想い</h1>
        
        <div style='font-size: 30px; color: var(--text);'>
          <p style='margin-bottom: 40px;'>
            現場で働く薬剤師の皆さん、今日もお疲れ様です。
          </p>
          
          <p style='margin-bottom: 40px;'>
            日々の業務の中で出会う、インシデント事例、疑義紹介、他職種との連携、そして部下の教育…。<br>
            これらは、<strong>教科書には決して載っていない「生きた知恵」</strong>です。
          </p>

          <p style='margin-bottom: 40px; background: #f0f7ff; padding: 30px; border-radius: 20px; border-left: 10px solid var(--primary); font-weight: 800;'>
            「日常の忙しさに埋もれてしまう、貴重な気づきと経験を形に残したい」
          </p>

          <p style='margin-bottom: 40px;'>
            そんな想いから、この <strong>PharmaShare</strong> は生まれました。<br>
            一人ひとりの経験を共有することが、誰かの明日の業務を助け、ひいては患者さんの安心に繋がると信じています。
          </p>

          <p style='margin-bottom: 60px;'>
            あなたの小さな気づきを、ぜひここで発信してください。<br>
            みんなで知恵を共有し、より良い薬剤師ライフを一緒に作っていきましょう！
          </p>

          <div style='text-align: right;'>
            <p style='font-size: 24px; color: var(--secondary); margin-bottom: 5px;'>PharmaShare 創設者</p>
            <p style='font-size: 36px; font-weight: 900;'>かたばみ</p>
          </div>
        </div>

        <div style='text-align:center; margin-top: 60px; border-top: 2px solid #eee; padding-top: 40px;'>
          <a href='/' class='btn-primary' style='text-decoration:none; display: inline-flex; align-items:center; justify-content:center; height: 80px; width: 300px; font-size: 28px;'>タイムラインへ</a>
        </div>
      </div>
    </div>
  "
  html
end

post '/update_profile' do
  redirect '/login_page' unless session[:user]
  
  # --- アイコン画像の保存処理 ---
  icon_filename = nil
  if params[:icon_image] && params[:icon_image][:tempfile]
    icon_filename = "icon_" + Time.now.to_i.to_s + "_" + params[:icon_image][:filename]
    save_path = "./public/uploads/#{icon_filename}"
    Dir.mkdir("./public/uploads") unless Dir.exist?("./public/uploads")
    File.open(save_path, 'wb') { |f| f.write(params[:icon_image][:tempfile].read) }
  end

  if icon_filename
    # 画像がある場合は、icon_pathも更新
    query("UPDATE users SET email = $1, bio = $2, icon_path = $3 WHERE user_name = $4", 
          [params[:email], params[:bio], icon_filename, session[:user]])
  else
    # 画像がない場合は、これまでの2つだけ更新
    query("UPDATE users SET email = $1, bio = $2 WHERE user_name = $3", 
          [params[:email], params[:bio], session[:user]])
  end
        
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
  # ヘッダーに「ログイン」とタイトルを表示
  header_menu("ログイン") + "
    <div class='container' style='max-width: 1000px;'> <div class='post-card' style='padding: 40px;'>
        <h2 style='text-align: center; color: var(--primary); font-size: 42px; margin-bottom: 15px;'>🔑 PharmaShareへようこそ</h2>
        <p style='font-size: 26px; color: var(--secondary); text-align: center; margin-bottom: 40px;'>
          薬剤師の知恵を共有し、現場をより良くするコミュニティ
        </p>

        <div style='display: flex; border-bottom: 3px solid #d2d2d7; margin-bottom: 40px;'>
          <button onclick='showAuth(\"login\")' id='tab-login' style='flex: 1; padding: 25px; border: none; background: none; font-weight: 800; border-bottom: 6px solid var(--primary); cursor: pointer; font-size: 32px; color: var(--text);'>ログイン</button>
          <button onclick='showAuth(\"signup\")' id='tab-signup' style='flex: 1; padding: 25px; border: none; background: none; color: var(--secondary); cursor: pointer; font-size: 32px;'>新規登録</button>
        </div>

        <form action='/auth' method='post' id='authForm'>
          <div style='margin-bottom: 25px;'>
            <input type='text' name='user_name' id='userName' placeholder='ユーザー名' required style='height: 90px; font-size: 30px !important;'>
          </div>
          <div style='margin-bottom: 25px;'>
            <input type='password' name='password' id='password' placeholder='パスワード' required style='height: 90px; font-size: 30px !important;'>
          </div>
          
          <div id='signup-extras' style='display: none; margin-top: 20px; padding: 30px; background: #fdfaf0; border-radius: 20px; border: 3px solid #faecc5;'>
            <label style='font-size: 28px; font-weight: 900; color: #856404; display: block; margin-bottom: 10px;'>🌟 本登録のメリット</label>
            <ul style='font-size: 24px; color: #856404; margin: 15px 0; padding-left: 35px; line-height: 1.8;'>
              <li>知恵を投稿して仲間に共有できる</li>
              <li>「お気に入り」を保存して後で見返せる</li>
              <li>自分の投稿実績がマイページに残る</li>
            </ul>
            <input type='email' name='email' id='emailField' placeholder='メールアドレス（本登録用）' style='height: 90px; font-size: 30px !important; background: white;'>
            <p style='font-size: 20px; color: var(--secondary); margin-top: 10px;'>※閲覧のみ（仮登録）の方は空欄でOKです</p>
          </div>

          <input type='hidden' name='mode' id='submitMode' value='login'>
          
          <button type='button' id='main-btn' onclick='handleAuth()' class='btn-primary' style='width: 100%; height: 100px; margin-top: 40px; font-size: 36px; font-weight: 900; border-radius: 16px;'>ログインする</button>
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
          // 切り替え時の線の太さを6pxに合わせて強調
          tabSignup.style.borderBottom = '6px solid var(--primary)';
          tabSignup.style.fontWeight = '800';
          tabSignup.style.color = 'var(--text)';
          tabLogin.style.borderBottom = 'none';
          tabLogin.style.fontWeight = 'normal';
          tabLogin.style.color = 'var(--secondary)';
          submitMode.value = 'signup';
        } else {
          signupExtras.style.display = 'none';
          mainBtn.innerText = 'ログインする';
          tabLogin.style.borderBottom = '6px solid var(--primary)';
          tabLogin.style.fontWeight = '800';
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
  
  html = header_menu("新規投稿") + "
    <div class='container' style='max-width: 1000px;'>
      <h1 style='font-size: 42px; margin-bottom: 10px;'>✍️ 投稿、情報を発信する</h1>
      
      <div style='background: #fff5f5; border: 3px solid #ff3b30; padding: 20px; border-radius: 12px; margin-bottom: 30px;'>
        <p style='color: #ff3b30; font-size: 26px; font-weight: 900; margin: 0; line-height: 1.4;'>
          ⚠️禁忌事項⚠️<br>
          個人や団体が特定される書き込みは絶対に禁忌です！プライバシーには細心の注意を払ってください。
        </p>
      </div>

      <div class='post-card' style='padding: 40px;'>
        <form action='/post' method='post' enctype='multipart/form-data'>
          <input type='hidden' name='parent_id' value='-1'>

          <div style='margin-bottom: 30px;'>
            <label style='font-size: 24px; font-weight: 800; color: var(--secondary); display: block; margin-bottom: 10px;'>カテゴリ</label>
            <select name='category' style='height: 80px; font-size: 28px !important; border: 2px solid #d2d2d7; width: 100%; border-radius: 12px;'>
  "
  CATEGORIES.each { |name, color| html += "<option value='#{name}'>#{name}</option>" }
  
  html += "
            </select>
          </div>

          <div style='margin-bottom: 30px;'>
            <label style='font-size: 24px; font-weight: 800; color: var(--secondary); display: block; margin-bottom: 10px;'>表題（タイトル）</label>
            <input type='text' name='title' placeholder='何についての気づきですか？' required style='height: 80px; font-size: 28px !important; width: 100%; border-radius: 12px; border: 2px solid #d2d2d7; padding: 0 15px;'>
          </div>

          <div style='margin-bottom: 30px;'>
            <label style='font-size: 24px; font-weight: 800; color: var(--secondary); display: block; margin-bottom: 10px;'>💊 薬剤名（任意）</label>
            <input type='text' name='drug_name' placeholder='例：アムロジピン' style='height: 80px; font-size: 28px !important; width: 100%; border-radius: 12px; border: 2px solid #d2d2d7; padding: 0 15px;'>
          </div>

          <div style='margin-bottom: 30px; padding: 25px; background: #f5f5f7; border-radius: 12px; border: 2px solid #d2d2d7;'>
            <label style='font-size: 26px; font-weight: 800; color: var(--text); display: block; margin-bottom: 15px;'>📷 画像添付（任意）</label>
            <input type='file' name='image' accept='image/*' style='font-size: 26px; width: 100%;'>
          </div>

          <div style='margin-bottom: 30px;'>
            <label style='font-size: 24px; font-weight: 800; color: var(--secondary); display: block; margin-bottom: 10px;'>内容</label>
            <textarea name='message' placeholder='日常の忙しさに埋もれてしまう貴重な経験を書き留めましょう...' rows='10' required style='font-size: 28px !important; padding: 20px; border: 2px solid #d2d2d7; width: 100%; border-radius: 12px; line-height: 1.5;'></textarea>
          </div>

          <button type='submit' class='btn-primary' style='width: 100%; height: 100px; font-size: 36px; font-weight: 900; border-radius: 18px;'>投稿する</button>
          
          <a href='/' style='display: block; text-align: center; margin-top: 30px; font-size: 26px; color: var(--secondary); text-decoration: none; font-weight: 600;'>キャンセルして戻る</a>
        </form>
      </div>
    </div>
  "
end

get '/robots.txt' do
  content_type 'text/plain'
  "User-agent: *\nAllow: /"
end