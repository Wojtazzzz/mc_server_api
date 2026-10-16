defmodule McServerApi.Ping.PublicIpTest do
  use ExUnit.Case, async: true

  alias McServerApi.Ping.Client

  test "allows public addresses" do
    assert Client.public_ip?({141, 94, 231, 66})
    assert Client.public_ip?({8, 8, 8, 8})
    assert Client.public_ip?({0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111})
  end

  test "refuses loopback, private and reserved addresses" do
    for ip <- [
          {127, 0, 0, 1},
          {10, 1, 2, 3},
          {172, 16, 0, 1},
          {192, 168, 1, 1},
          {169, 254, 169, 254},
          {100, 64, 0, 1},
          {0, 0, 0, 0},
          {224, 0, 0, 1},
          {0, 0, 0, 0, 0, 0, 0, 1},
          {0xFD00, 0, 0, 0, 0, 0, 0, 1},
          {0xFE80, 0, 0, 0, 0, 0, 0, 1},
          {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 0x0001}
        ] do
      refute Client.public_ip?(ip), "#{inspect(ip)} should be refused"
    end
  end

  test "an internal address is reported as an error, not pinged" do
    assert {:error, :forbidden_address} = Client.status("127.0.0.1:6379", allow_private: false)
    assert {:error, :forbidden_address} = Client.status("localhost", allow_private: false)
  end
end
