ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

configure do
  enable :sessions
end

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content="")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { user: "admin" }}
  end

  def test_index
    create_document("about.txt")
    create_document("changes.md")

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-type"]
    assert_includes last_response.body, 'about.txt'
    assert_includes last_response.body, 'changes.md'
  end

  def test_viewing_text_document
    create_document("history.txt", "Matsumoto has said that Ruby was conceived in 1993.")

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-type"]
    assert_includes last_response.body, 'Matsumoto has said that Ruby was conceived in 1993.'
  end

  def test_markdown
    create_document("markdown.md", "*Italic*, **bold**, and `monospace`.")

    get "/markdown.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-type"]
    assert_includes last_response.body, "<em>Italic</em>, <strong>bold</strong>, and <code>monospace</code>."
  end

  def test_not_exist
    get "/notafile.ext"
    assert_equal 302, last_response.status

    assert_equal 'notafile.ext does not exist.', session[:message]
  end

  def test_file_edit
    create_document("about.txt")

    get "/about.txt/edit", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %Q[<button type="submit"]
  end

  def test_file_edit_signed_out
    create_document("about.txt")

    get "/about.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to perform that action.", session[:message]
  end

  def test_file_update
    post "/about.txt", {updated_text: "new text"}, admin_session
    assert_equal 302, last_response.status

    assert_equal 'about.txt has been updated!', session[:message]

    get "/about.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new text"
  end

  def test_file_update_signed_out
    post "/about.txt", {updated_text: "new text"}
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to perform that action.", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<label>Add a new document:"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_new_document_form_signed_out
    get "/new"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to perform that action.", session[:message]
  end

  def test_create_new_document
    post "/new", {new_doc: "new_document.txt"}, admin_session
    assert_equal 302, last_response.status

    assert_equal "new_document.txt was created.", session[:message]

    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new_document.txt"
  end

  def test_create_new_document_signed_out
    post "/new", {new_doc: "new_document.txt"}
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to perform that action.", session[:message]
  end

  def test_document_name_blank
    post "/new", {new_doc: ""}, admin_session
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "A name is required."
  end

  def test_document_extension_invalid
    post "/new", {new_doc: "name"}, admin_session
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "File name must end in .txt or .md"
  end

  def test_file_delete
    create_document("about.txt")
    post "/about.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "about.txt has been deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/about.txt")
  end

  def test_file_delete_signed_out
    create_document("about.txt")

    post "/about.txt/delete"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to perform that action.", session[:message]
  end

  def test_file_duplicate
    create_document("about.txt")

    post "/about.txt/duplicate", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "about(1).txt was created.", session[:message]
  end


  def test_file_duplicate_signed_out
    create_document("about.txt")

    post "/about.txt/duplicate"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to perform that action.", session[:message]
  end

  def test_signin_form
    get "/users/signin"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<form action="
    assert_includes last_response.body, "<button type="
  end

  def test_signin
    post '/users/signin', username: "admin", password: "secret"
    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:user]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
  end

  def test_failed_signin
    post '/users/signin', username: "user", password: "whoops"
    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid credentials"
  end

  def test_signout
    get "/", {}, {"rack.session" => {user: "admin" }}
    assert_includes last_response.body, "Signed in as admin"

    post '/users/signout'
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_nil session[:user]
    assert_includes last_response.body, %q(<button type="signin">)
  end
end
