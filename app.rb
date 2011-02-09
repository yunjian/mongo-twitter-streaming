require 'net/http'
require 'uri'

STREAMING_URL = 'http://stream.twitter.com/1/statuses/filter.json?track=%23'
TWITTER_USERNAME = ENV['TWITTER_USERNAME']
TWITTER_PASSWORD = ENV['TWITTER_PASSWORD']

configure do
  if ENV['MONGOHQ_URL']
    uri = URI.parse(ENV['MONGOHQ_URL'])
    conn = Mongo::Connection.from_uri(ENV['MONGOHQ_URL'])
    DB = conn.db(uri.path.gsub(/^\//, ''))
  else
    DB = Mongo::Connection.new.db("mongo-twitter-streaming")
  end
  
  DB.create_collection("tweets", :capped => true, :size => 16777216)
end

get '/' do
  content_type 'text/html', :charset => 'utf-8'
  @tweets = DB['tweets'].find({}, :sort => [[ '$natural', :desc ]])
  erb :index
end

EM.schedule do
  http = EM::HttpRequest.new(STREAMING_URL).get :head => { 'Authorization' => [ TWITTER_USERNAME, TWITTER_PASSWORD ] }
  buffer = ""
  http.stream do |chunk|
    buffer += chunk
    while line = buffer.slice!(/.+\r?\n/)
      tweet = JSON.parse(line)
      DB['tweets'].insert(tweet) if tweet['text']
      url = URI.parse('http://silviobasta.heroku.com/update')
      req = Net::HTTP::Post.new(url.path)
      req.basic_auth UPDATE_USERNAME, UPDATE_PASSWORD
      req.set_form_data(tweet)
      Net::HTTP.new(url.host, url.port).start { http.request(req) }
    end
  end
end