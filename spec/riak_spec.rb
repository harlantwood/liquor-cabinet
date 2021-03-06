require_relative "spec_helper"

describe "App with Riak backend" do
  include Rack::Test::Methods
  include RemoteStorage::Riak

  before do
    purge_all_buckets
  end

  describe "GET public data" do
    before do
      object = data_bucket.new("jimmy:public:foo")
      object.content_type = "text/plain"
      object.data = "some text data"
      object.store

      get "/jimmy/public/foo"
    end

    it "returns the value on all get requests" do
      last_response.status.must_equal 200
      last_response.body.must_equal "some text data"
    end

    it "has a Last-Modified header set" do
      last_response.status.must_equal 200
      last_response.headers["Last-Modified"].wont_be_nil

      now = Time.now
      last_modified = DateTime.parse(last_response.headers["Last-Modified"])
      last_modified.year.must_equal now.year
      last_modified.day.must_equal now.day
    end
  end

  describe "GET data with custom content type" do
    before do
      object = data_bucket.new("jimmy:public:magic")
      object.content_type = "text/magic"
      object.raw_data = "some text data"
      object.store
    end

    it "returns the value with the correct content type" do
      get "/jimmy/public/magic"

      last_response.status.must_equal 200
      last_response.content_type.must_equal "text/magic"
      last_response.body.must_equal "some text data"
    end
  end

  describe "private data" do
    before do
      object = data_bucket.new("jimmy:documents:foo")
      object.content_type = "text/plain"
      object.data = "some private text data"
      object.store

      auth = auth_bucket.new("jimmy:123")
      auth.data = ["documents", "public"]
      auth.store
    end

    describe "GET" do
      it "returns the value" do
        header "Authorization", "Bearer 123"
        get "/jimmy/documents/foo"

        last_response.status.must_equal 200
        last_response.body.must_equal "some private text data"
      end
    end

    describe "GET nonexisting key" do
      it "returns a 404" do
        header "Authorization", "Bearer 123"
        get "/jimmy/documents/somestupidkey"

        last_response.status.must_equal 404
      end
    end

    describe "PUT" do
      before do
        header "Authorization", "Bearer 123"
      end

      describe "with implicit content type" do
        before do
          put "/jimmy/documents/bar", "another text"
        end

        it "saves the value" do
          last_response.status.must_equal 200
          last_response.body.must_equal ""
          data_bucket.get("jimmy:documents:bar").data.must_equal "another text"
        end

        it "stores the data as plain text with utf-8 encoding" do
          data_bucket.get("jimmy:documents:bar").content_type.must_equal "text/plain; charset=utf-8"
        end

        it "indexes the data set" do
          indexes = data_bucket.get("jimmy:documents:bar").indexes
          indexes["user_id_bin"].must_be_kind_of Set
          indexes["user_id_bin"].must_include "jimmy"

          indexes["directory_bin"].must_include "documents"
        end
      end

      describe "with explicit content type" do
        before do
          header "Content-Type", "application/json"
          put "/jimmy/documents/jason", '{"foo": "bar", "unhosted": 1}'
        end

        it "saves the value (as JSON)" do
          last_response.status.must_equal 200
          data_bucket.get("jimmy:documents:jason").data.must_be_kind_of Hash
          data_bucket.get("jimmy:documents:jason").data.must_equal({"foo" => "bar", "unhosted" => 1})
        end

        it "uses the requested content type" do
          data_bucket.get("jimmy:documents:jason").content_type.must_equal "application/json"
        end

        it "delivers the data correctly" do
          header "Authorization", "Bearer 123"
          get "/jimmy/documents/jason"

          last_response.body.must_equal '{"foo":"bar","unhosted":1}'
          last_response.content_type.must_equal "application/json"
        end
      end

      describe "with arbitrary content type" do
        before do
          header "Content-Type", "text/magic"
          put "/jimmy/documents/magic", "pure magic"
        end

        it "saves the value" do
          last_response.status.must_equal 200
          data_bucket.get("jimmy:documents:magic").raw_data.must_equal "pure magic"
        end

        it "uses the requested content type" do
          data_bucket.get("jimmy:documents:magic").content_type.must_equal "text/magic"
        end

        it "delivers the data correctly" do
          header "Authorization", "Bearer 123"
          get "/jimmy/documents/magic"

          last_response.body.must_equal "pure magic"
          last_response.content_type.must_equal "text/magic"
        end
      end

      describe "with content type containing the encoding" do
        before do
          header "Content-Type", "application/json; charset=UTF-8"
          put "/jimmy/documents/jason", '{"foo": "bar", "unhosted": 1}'
        end

        it "saves the value (as JSON)" do
          last_response.status.must_equal 200
          data_bucket.get("jimmy:documents:jason").data.must_be_kind_of Hash
          data_bucket.get("jimmy:documents:jason").data.must_equal({"foo" => "bar", "unhosted" => 1})
        end

        it "uses the requested content type" do
          data_bucket.get("jimmy:documents:jason").content_type.must_equal "application/json; charset=UTF-8"
        end

        it "delivers the data correctly" do
          get "/jimmy/documents/jason"

          last_response.body.must_equal '{"foo":"bar","unhosted":1}'
          last_response.content_type.must_equal "application/json; charset=UTF-8"
        end
      end

      context "with binary data" do
        context "binary charset in content-type header" do
          before do
            header "Content-Type", "image/jpeg; charset=binary"
            filename = File.join(File.expand_path(File.dirname(__FILE__)), "fixtures", "rockrule.jpeg")
            @image = File.open(filename, "r").read
            put "/jimmy/documents/jaypeg", @image
          end

          it "uses the requested content type" do
            get "/jimmy/documents/jaypeg"

            last_response.status.must_equal 200
            last_response.content_type.must_equal "image/jpeg; charset=binary"
          end

          it "delivers the data correctly" do
            get "/jimmy/documents/jaypeg"

            last_response.status.must_equal 200
            last_response.body.must_equal @image
          end

          it "indexes the binary set" do
            indexes = binary_bucket.get("jimmy:documents:jaypeg").indexes
            indexes["user_id_bin"].must_be_kind_of Set
            indexes["user_id_bin"].must_include "jimmy"

            indexes["directory_bin"].must_include "documents"
          end
        end

        context "no binary charset in content-type header" do
          before do
            header "Content-Type", "image/jpeg"
            filename = File.join(File.expand_path(File.dirname(__FILE__)), "fixtures", "rockrule.jpeg")
            @image = File.open(filename, "r").read
            put "/jimmy/documents/jaypeg", @image
          end

          it "uses the requested content type" do
            get "/jimmy/documents/jaypeg"

            last_response.status.must_equal 200
            last_response.content_type.must_equal "image/jpeg"
          end

          it "delivers the data correctly" do
            get "/jimmy/documents/jaypeg"

            last_response.status.must_equal 200
            last_response.body.must_equal @image
          end

          it "indexes the binary set" do
            indexes = binary_bucket.get("jimmy:documents:jaypeg").indexes
            indexes["user_id_bin"].must_be_kind_of Set
            indexes["user_id_bin"].must_include "jimmy"

            indexes["directory_bin"].must_include "documents"
          end
        end
      end

      context "with escaped key" do
        before do
          put "/jimmy/documents/http%3A%2F%2F5apps.com", "super website"
        end

        it "delivers the data correctly" do
          header "Authorization", "Bearer 123"
          get "/jimmy/documents/http%3A%2F%2F5apps.com"

          last_response.body.must_equal 'super website'
        end
      end

      context "invalid JSON" do
        context "empty body" do
          before do
            header "Content-Type", "application/json"
            put "/jimmy/documents/jason", ""
          end

          it "saves an empty JSON object" do
            last_response.status.must_equal 200
            data_bucket.get("jimmy:documents:jason").data.must_be_kind_of Hash
            data_bucket.get("jimmy:documents:jason").data.must_equal({})
          end
        end

        context "unparsable JSON" do
          before do
            header "Content-Type", "application/json"
            put "/jimmy/documents/jason", "foo"
          end

          it "returns a 422" do
            last_response.status.must_equal 422
          end
        end
      end
    end

    describe "DELETE" do
      before do
        header "Authorization", "Bearer 123"
      end

      it "removes the key" do
        delete "/jimmy/documents/foo"

        last_response.status.must_equal 204
        lambda {
          data_bucket.get("jimmy:documents:foo")
        }.must_raise Riak::HTTPFailedRequest
      end

      context "binary data" do
        before do
          header "Content-Type", "image/jpeg; charset=binary"
          filename = File.join(File.expand_path(File.dirname(__FILE__)), "fixtures", "rockrule.jpeg")
          @image = File.open(filename, "r").read
          put "/jimmy/documents/jaypeg", @image
        end

        it "removes the main object" do
          delete "/jimmy/documents/jaypeg"

          last_response.status.must_equal 204
          lambda {
            data_bucket.get("jimmy:documents:jaypeg")
          }.must_raise Riak::HTTPFailedRequest
        end

        it "removes the binary object" do
          delete "/jimmy/documents/jaypeg"

          last_response.status.must_equal 204
          lambda {
            binary_bucket.get("jimmy:documents:jaypeg")
          }.must_raise Riak::HTTPFailedRequest
        end
      end
    end
  end

  describe "unauthorized access" do
    before do
      auth = auth_bucket.new("jimmy:123")
      auth.data = ["documents", "public"]
      auth.store

      header "Authorization", "Bearer 321"
    end

    describe "GET" do
      it "returns a 403" do
        get "/jimmy/documents/foo"

        last_response.status.must_equal 403
      end
    end

    describe "PUT" do
      it "returns a 403" do
        put "/jimmy/documents/foo", "some text"

        last_response.status.must_equal 403
      end
    end

    describe "DELETE" do
      it "returns a 403" do
        delete "/jimmy/documents/foo"

        last_response.status.must_equal 403
      end
    end
  end
end
