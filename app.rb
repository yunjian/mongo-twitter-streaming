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

# req = Net::HTTP.get_response(URI.parse("http://#{TWITTER_USERNAME}:#{TWITTER_PASSWORD}@stream.twitter.com/1/statuses/filter.json?track=%23egypt"))
# print req.body

Net::HTTP.start('stream.twitter.com') {|http|
  req = Net::HTTP::Get.new('/1/statuses/filter.json?track=%23egypt')
  req.basic_auth TWITTER_USERNAME, TWITTER_PASSWORD
  response = http.request(req)
  print response.body
}

puts 'before EM'
EM.schedule do
  puts 'starting EM'
  http = EM::HttpRequest.new(STREAMING_URL).post(:head => { 'Authorization' => [ TWITTER_USERNAME, TWITTER_PASSWORD ] }, :query => { "track" => "#silviobasta" })
  buffer = ""
  http.headers { |hash|  p [:headers, hash] }
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
  http.callback{ |http|
    puts "CAZZO"
    puts "1 #{http.response_header.status}"
    puts "2 #{http.response_header}"
    puts "3 #{http.response}"
  }
  puts http.error?
  puts http.response
  puts http.response_header
  puts http.response_header.status
  http.errback { |h|
    puts h.inspect
    puts h.send(:data).inspect
  }
  puts http.inspect
  puts 'stream ended'
end