require 'net/http'
require 'uri'
require 'tweetstream'
require 'sinatra'

TWITTER_USERNAME = ENV['TWITTER_USERNAME']
TWITTER_PASSWORD = ENV['TWITTER_PASSWORD']
DIBAKE_API_KEY = ENV['DIBAKE_API_KEY']

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
  end.track('#dibake') do |status|
    vote = 'none'
    if status.text[/#dibake (\d+) yes or no/]
      topic = $1
      vote = 'none'
    elsif status.text[/#dibake (\d+) no/]
      topic = $1
      vote = 'contra'
    elsif status.text[/#dibake (\d+) yes/]
      topic = $1
      vote = 'concur'
    end
    puts "[#{topic}] [#{vote}] #{status.text}"
    if vote != 'none'
        res = Net::HTTP.post_form(URI.parse("http://dibake.com/api/#{DIBAKE_API_KEY}"),
                          {'twitter_id' => "#{status.user.screen_name}", 
			  'status' => "#{status.text}",
			  'topic' => "#{topic}",
			  'vote' => "#{vote}"
			  })
    end
    tweet = { :text => status.text, :user => { :screen_name => status.user.screen_name } }
    DB['tweets'].insert(tweet)
  end
  puts 'end'
end
