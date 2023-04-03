require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, 'super secret'
end

helpers do
  def duplicate_name(filename)
    extension = filename[-3..-1] == ".md" ? filename.slice!(".md") : filename.slice!(".txt")
    num = filename.slice!(/\(\d+\)/)

    if num
      num = num[1..-2].to_i + 1
      num = "(" + num.to_s + ")"
    else
      num = "(1)"
    end

    filename + num + extension
  end

  def render_markdown(path)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
    markdown.render(path)
  end

  def load_file(path)
    content = File.read(path)

    if File.extname(path) == ".md"
      erb render_markdown(content)
    elsif File.extname(path) == ".txt"
      headers["Content-Type"] = "text/plain"
      content
    end
  end

  def validate_file_name(name)
    if name == ""
      session[:message] = "A name is required."
      redirect "/new"
    elsif name[-3..-1] != ".md" && name[-4..-1] != ".txt"
      session[:message] = "File name must end in .txt or .md"
      redirect "/new"
    end
  end

  def validate_logged_in
    unless session[:user]
    session[:message] = "You must be signed in to perform that action."
      redirect "/"
    end
  end

  def valid_credentials?(username, password)
    credentials = load_user_credentials

    if credentials.key?(username)
      bcrypt_password = BCrypt::Password.new(credentials[username])
      bcrypt_password == password
    else
      false
    end
  end
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map { |path| File.basename(path) }.sort
  erb :index
end

get "/new" do
  validate_logged_in
  erb :new
end

post "/new" do
  validate_logged_in

  file_name = params[:new_doc].downcase
  validate_file_name(file_name)

  File.open(File.join(data_path, file_name), "w") { |file| file.write }
  session[:message] = "#{file_name} was created."
  redirect "/"
end

get "/:filename" do
  path = File.join(data_path, params[:filename])

  if File.exist? path
    load_file(path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

get "/:filename/edit" do
  validate_logged_in

  path = File.join(data_path, params[:filename])

  if File.exist? path
    @title = params[:filename]
    @text = File.read(path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end

  erb :edit
end

post "/:filename" do
  validate_logged_in

  path = File.join(data_path, params[:filename])
  File.write(path, params[:updated_text])

  session[:message] = "#{params[:filename]} has been updated!"
  redirect "/"
end

post "/:filename/delete" do
  validate_logged_in

  path = File.join(data_path, params[:filename])
  File.delete(path)

   session[:message] = "#{params[:filename]} has been deleted."
   redirect "/"
end

post "/:filename/duplicate" do
  validate_logged_in

  file_name = duplicate_name(params[:filename].downcase)

  File.open(File.join(data_path, file_name), "w") { |file| file.write }
  session[:message] = "#{file_name} was created."
  redirect "/"
end

get "/users/signin" do
  erb :signin
end

post '/users/signin' do
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:user] = params[:username]
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post '/users/signout' do
  session.delete(:user)
  session[:message] = "You have been signed out."
  redirect "/"
end
