require 'net/http'
require 'uri'
# require 'sinatra'
# require 'eventmachine'
# require 'em-http-request'
# require 'json'

STREAMING_URL = 'http://stream.twitter.com/1/statuses/filter.json'
TWITTER_USERNAME = ENV['TWITTER_USERNAME']
TWITTER_PASSWORD = ENV['TWITTER_PASSWORD']
UPDATE_USERNAME = ENV['UPDATE_USERNAME']
UPDATE_PASSWORD = ENV['UPDATE_PASSWORD']

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

puts 'before EM'
EM.schedule do
  puts 'starting EM'
  http = EM::HttpRequest.new(STREAMING_URL).get(:head => { 'Authorization' => [ TWITTER_USERNAME, TWITTER_PASSWORD ] }, :query => { "track" => "#truth" })
  buffer = ""
  puts 'before stream'
  http.stream do |chunk|
    buffer += chunk
    puts "check: #{chunk}"
    while line = buffer.slice!(/.+\r?\n/)
      tweet = JSON.parse(line)
      DB['tweets'].insert(tweet) if tweet['text']
      puts "#{tweet['user']['screen_name']} | #{tweet['text']} | #{tweet['user']['location']} | #{tweet['created_at']}"
      puts
      res = Net::HTTP.post_form(URI.parse("http://#{UPDATE_USERNAME}:#{UPDATE_PASSWORD}@silviobasta.heroku.com/update"), tweet)
    end
  end
  puts 'stream ended'
end