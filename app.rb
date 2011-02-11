require 'net/http'
require 'uri'
require 'tweetstream'
require 'sinatra'
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
  @tweets = DB['tweets'].find({}, :limit => 5, :sort => [[ '$natural', :desc ]])
  erb :index
end

puts 'start'
EM.schedule do
  TweetStream::Client.new(TWITTER_USERNAME, TWITTER_PASSWORD).on_delete do |status_id, user_id|
    # Tweet.delete(status_id)
    puts "#{status_id} deleted"
  end.on_limit do |skip_count|
    puts "limited, skip count #{skip_count}"
  end.track('#silviobasta') do |status|
    puts "[#{status.user.screen_name}] #{status.text}"
    tweet = { :text => status.text, :user => { :screen_name => status.user.screen_name } }
    DB['tweets'].insert(tweet)
    res = Net::HTTP.post_form(URI.parse("http://#{UPDATE_USERNAME}:#{UPDATE_PASSWORD}@silviobasta.heroku.com/update"), tweet)
  end
  puts 'end'
end