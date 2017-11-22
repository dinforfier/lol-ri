# This util observes live LoL game and stores fetched game data
# Usage: ruby scrap.rb <GAME_ID> <REGION> <KEY>
# <GAME_ID> <REGION> <KEY> params of live games can be obtained here <URL>
# Data is stored in ./data/<REGION>/<GAMEID> folder

require 'json'
require 'faraday'
require 'fileutils'

GAMEID=ARGV[1]
REGION=ARGV[2]
KEY=ARGV[0]

if !GAMEID || !REGION || !KEY
  puts 'USAGE: ruby scrap.rb <GAME_ID> <REGION> <KEY>'
  exit
end

CONN=Faraday.new
GAME_DATA_DIR=File.join('./data', REGION, GAMEID)

def build_url(method, region, game_id, object_id=1)
  "http://spectator.#{region}.lol.riotgames.com/observer-mode/rest/consumer/#{method}/#{region}/#{game_id}/#{object_id}/token"
end

def build_current_game_url(method, object_id=1)
  build_url(method, REGION, GAMEID, object_id)
end

def get_game_meta_data
  url = build_current_game_url('getGameMetaData')
  resp = CONN.get(url)
  raise unless resp.status == 200
  JSON.parse(resp.body)
end

def get_last_chunk_info
  url = build_current_game_url('getLastChunkInfo')
  resp = CONN.get(url)
  raise unless resp.status == 200
  JSON.parse(resp.body)
end

def get_chunk_data(chunk_id)
  url = build_current_game_url('getGameDataChunk', chunk_id)
  resp = CONN.get(url)
  raise unless resp.status == 200
  resp.body
end

def get_key_frame_data(key_frame_id)
  url = build_current_game_url('getKeyFrame', key_frame_id)
  resp = CONN.get(url)
  raise unless resp.status == 200
  resp.body
end

def store_chunk_data(key_frame_id, chunk_id, data)
  file_path = File.join(GAME_DATA_DIR, "key_#{key_frame_id}_chunk_#{chunk_id}.data")
  f = File.new(file_path, 'w')
  f.write(data)
  f.close
end

def store_key_frame_data(key_frame_id, data)
  file_path = File.join(GAME_DATA_DIR, "key_#{key_frame_id}.data")
  f = File.new(file_path, 'w')
  f.write(data)
  f.close
end

def store_game_meta_data
  data = { key: KEY, id: GAMEID }.to_json
  file_path = File.join(GAME_DATA_DIR, "meta.json")
  f = File.new(file_path, 'w')
  f.write(data)
  f.close
end

last_key_frame_id = nil

FileUtils.mkdir_p(GAME_DATA_DIR)
store_game_meta_data

puts "Observing Started for #{GAMEID} in #{REGION}"

begin
  chunk_info = get_last_chunk_info
  chunk_id = chunk_info['chunkId']
  key_frame_id = chunk_info['keyFrameId']

  # Game is started
  if chunk_id != 0
    if last_key_frame_id != key_frame_id
      key_frame_data = get_key_frame_data(key_frame_id)
      store_key_frame_data(key_frame_id, key_frame_data)
      last_key_frame_id = key_frame_id
      puts "Got key frame ##{key_frame_id}"
    end

    chunk_data = get_chunk_data(chunk_id)
    store_chunk_data(key_frame_id, chunk_id, chunk_data)
    puts "Got chunk ##{chunk_id}"
  else
    puts 'Waiting for game start'
  end

  sleep chunk_info['nextAvailableChunk']/1000 + 1
end while chunk_info['endGameChunkId'] != chunk_id
