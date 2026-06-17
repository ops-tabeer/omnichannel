class Jivo::Tools::DnsValidator
  PRIVATE_IP_RANGES = [
    IPAddr.new('127.0.0.0/8'),
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.168.0.0/16'),
    IPAddr.new('169.254.0.0/16'),
    IPAddr.new('::1'),
    IPAddr.new('fc00::/7'),
    IPAddr.new('fe80::/10')
  ].freeze

  class Error < StandardError; end
  class PrivateIpBlocked < Error; end
  class ResolutionFailed < Error; end
  class RebindingDetected < Error; end

  attr_reader :hostname, :ip_address

  def initialize(hostname)
    @hostname = hostname
  end

  def validate!
    @ip_address = resolve_ip
    ensure_public!(@ip_address)
    self
  end

  def reverify!
    raise Error, 'validate! must be called before reverify!' if @ip_address.nil?

    current = resolve_ip
    return if current == @ip_address

    raise RebindingDetected,
          "DNS rebinding detected: #{@hostname} resolved to #{@ip_address} initially but #{current} on re-check"
  end

  private

  def resolve_ip
    IPAddr.new(Resolv.getaddress(@hostname))
  rescue Resolv::ResolvError, SocketError => e
    raise ResolutionFailed, "DNS resolution failed for #{@hostname}: #{e.message}"
  end

  def ensure_public!(ip)
    return unless PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }

    raise PrivateIpBlocked, "Request blocked: #{@hostname} resolves to private IP address #{ip}"
  end
end
