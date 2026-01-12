require 'sinatra'
require 'sqlite3'

# Renderなどの環境でポート番号を正しく認識させる設定
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

# データベースの初期設定（テーブルがなければ作る）
def setup_db
  db = SQLite3::Database.new 'posts.db'
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      content TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  SQL
  db.close
end

# 起動時に一度だけ実行
setup_db

# トップページ：投稿一覧を表示
get '/' do
  db = SQLite3::Database.new 'posts.db'
  # 配列ではなくハッシュ形式で結果を受け取れるようにすると便利
  db.results_as_hash = true
  @posts = db.execute("SELECT * FROM posts ORDER BY created_at DESC")
  db.close
  
  # シンプルなHTMLを表示
  erb :index
end

# 投稿機能
post '/post' do
  content = params[:content]
  if content && content.strip != ""
    db = SQLite3::Database.new 'posts.db'
    db.execute("INSERT INTO posts (content) VALUES (?)", [content])
    db.close
  end
  redirect '/'
end

# 表示用のHTMLテンプレート
helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end
end

__END__

@@index
<!DOCTYPE html>
<html>
<head>
  <title>薬剤師SNS</title>
  <style>
    body { font-family: sans-serif; max-width: 600px; margin: 20px auto; padding: 0 10px; }
    form { margin-bottom: 20px; }
    textarea { width: 100%; height: 60px; }
    .post { border-bottom: 1px solid #ccc; padding: 10px 0; }
    .time { font-size: 0.8em; color: #666; }
  </style>
</head>
<body>
  <h1>薬剤師SNS (Beta)</h1>
  <form action="/post" method="post">
    <textarea name="content" placeholder="今何してる？"></textarea><br>
    <button type="submit">投稿する</button>
  </form>

  <% @posts.each do |post| %>
    <div class="post">
      <div><%= h(post['content']) %></div>
      <div class="time"><%= post['created_at'] %></div>
    </div>
  <% end %>
</body>
</html>