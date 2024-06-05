import requests
import json

login_ip = "103.63.136.115:32751"
# ip = "neutron-svc.openstack.svc.cluster.local"
ip = "103.63.136.115:32750"
token = {
    "X-Auth-Token": "gAAAAABmJeM4TzaEsiAdkqLNY_B_d6CzzYa_vpgff3MdTgmz0pI6pfTOnw5grIUckcwDClIOlwNMKlA2sLGUDMzByJJRp7knupq3n7qNsYWYQWGe5_gjk9SmxJjxstcooL1dz0YxZt-SR_b5VTKDLwLzcYnx3wJkMxOqkVB8xLbgZ5XiE8NF-fc"
}
device_id = ""
# 110
# public_network_id = "ecc5f09b-1edb-496f-8496-2047a158ad31"
# 58
# public_network_id = "a031a442-7331-4a4b-937a-db843c10e245"
# 130
public_network_id = "9546aa2f-d95d-4f00-9454-2a1ec8628747"
# 正式
# network_id="2aed5310-a921-4603-87b1-a993e25408cf"
def login():
    global token
    body = {
        "auth": {
            "identity": {
                "methods": ["password"],
                "password": {
                    "user": {
                        "domain": {"name": "default"},
                        "name": "neutron",
                        "password": "password",
                    }
                },
            },
            "scope": {"project": {"domain": {"id": "default"}, "name": "service"}},
        }
    }
    res = requests.post(f"http://{login_ip}/v3/auth/tokens", json=body)
    if res.ok:
        token = {"X-Auth-Token": res.headers.get("X-Subject-Token")}


def check_network(name):
    res = requests.get(f"http://{ip}/v2.0/networks?name={name}", headers=token)
    if res.status_code == 401:
        login()
        res = requests.get(f"http://{ip}/v2.0/networks?name={name}", headers=token)
    if not res.json().get("networks") or len(res.json().get("networks")) == 0:
        print("network not found,will create")
        create_network(name)
    else:
        print("network already exists,will check subnet")
        check_subnet("vm_test_subnet", res.json().get("networks")[0].get("id"))


def check_subnet(name, id):
    res = requests.get(f"http://{ip}/v2.0/subnets?name={name}", headers=token)
    if res.status_code == 401:
        login()
        res = requests.get(f"http://{ip}/v2.0/subnets?name={name}", headers=token)
    if not res.json().get("subnets") or len(res.json().get("subnets")) == 0:
        print("subnet not found,will create")
        create_subnets(id)
    else:
        print("subnet already exists,will check interface port")
        check_interface_port(
            "vm_test_interface_port",
            id,
            res.json().get("subnets")[0].get("id"),
            device_id,
        )


def check_port(name, network_id):
    res = requests.get(f"http://{ip}/v2.0/ports?name={name}", headers=token)
    if res.status_code == 401:
        login()
        res = requests.get(f"http://{ip}/v2.0/ports?name={name}", headers=token)
    if not res.json().get("ports") or len(res.json().get("ports")) == 0:
        print("port not found,will create")
        create_port("vm_test_port", network_id)
    else:
        print("port already exists,will bind floatingip")
        print(res.json().get("ports")[0].get("id"))
        bind_floatingip(res.json().get("ports")[0].get("id"))


def check_interface_port(name, network_id, subnet_id, device_id):
    res = requests.get(f"http://{ip}/v2.0/ports?name={name}", headers=token)
    if res.status_code == 401:
        login()
        res = requests.get(f"http://{ip}/v2.0/ports?name={name}", headers=token)
    if not res.json().get("ports") or len(res.json().get("ports")) == 0:
        print("interface port not found,will create")
        create_interface_port(network_id, subnet_id, device_id)
    else:
        print("interface port already exists,will create port")
        check_port("vm_test_port", network_id)


def check_router(name):
    res = requests.get(f"http://{ip}/v2.0/routers?name={name}", headers=token)

    if res.status_code == 401:
        login()
        res = requests.get(f"http://{ip}/v2.0/routers?name={name}", headers=token)
    if not res.json().get("routers") or len(res.json().get("routers")) == 0:
        print("router not found,will create")
        id = create_router("vm_test_router")
        return id
    else:
        print("router already exists")
        return res.json().get("routers")[0].get("id")


def bind_floatingip(port_id):
    try:
        res = requests.get(
            f"http://{ip}/v2.0/floatingips?port_id={port_id}&limit=1",
            timeout=30,
            headers=token,
        )
        if len(res.json().get("floatingips")) > 0:
            print(res.json().get("floatingips")[0])
            return
        res = requests.get(
            f"http://{ip}/v2.0/floatingips?status=down&limit=1",
            timeout=30,
            headers=token,
        )
        res.raise_for_status()  # 检查是否有错误发生
        print("Request successful!",res.json().get("floatingips")[0].get("id"))
        if res.ok and res.json().get("floatingips")[0].get("id"):
            fid = res.json().get("floatingips")[0].get("id")
            tmp = {"floatingip": {"port_id": port_id}}
            res=requests.put(
                f"http://{ip}/v2.0/floatingips/{fid}",
                json=tmp,
                timeout=30,
                headers=token,
            )
            print(res.text)
    except requests.exceptions.Timeout:
        print("Timeout error occurred. Request timed out after 30 seconds.")
    except requests.exceptions.RequestException as e:
        print("Error occurred:", e)


def create_router(name):
    body = {
        "router": {
            "name": name,
            "admin_state_up": True,
            "external_gateway_info": {
                "network_id": public_network_id,
                "enable_snat": True,
            },
        }
    }
    try:
        print(token)
        res = requests.post(
            f"http://{ip}/v2.0/routers", json=body, timeout=30, headers=token
        )
        res.raise_for_status()  # 检查是否有错误发生
        print("Request successful!", res.text)
        if res.ok and res.json().get("router").get("id"):
            return res.json().get("router").get("id")
    except requests.exceptions.Timeout:
        print("Timeout error occurred. Request timed out after 30 seconds.")
    except requests.exceptions.RequestException as e:
        print("Error occurred:", e)


def create_port(name, network_id):
    body = {
        "port": {
            "name": name,
            "admin_state_up": True,
            "network_id": network_id,
            "port_security_enabled": False,
        }
    }
    try:
        res = requests.post(
            f"http://{ip}/v2.0/ports", json=body, timeout=30, headers=token
        )
        res.raise_for_status()  # 检查是否有错误发生
        print("Request successful!")
        if res.ok and res.json().get("port").get("id"):
            bind_floatingip(res.json().get("port").get("id"))
    except requests.exceptions.Timeout:
        print("Timeout error occurred. Request timed out after 30 seconds.")
    except requests.exceptions.RequestException as e:
        print("Error occurred:", e)


def create_interface_port(network_id, subnet_id, device_id):
    body = {
        "name":"vm_test_interface_port",
    "subnet_id": subnet_id
    }
    try:
        res = requests.put(
            f"http://{ip}/v2.0/routers/{device_id}/add_router_interface", json=body, timeout=30, headers=token
        )
        res.raise_for_status()  # 检查是否有错误发生
        print("Request successful!", res.json())
        if res.ok and res.json().get("id"):
            create_port("vm_test_port", network_id)
    except requests.exceptions.Timeout:
        print("Timeout error occurred. Request timed out after 30 seconds.")
    except requests.exceptions.RequestException as e:
        print("Error occurred:", e)


def create_subnets(id):
    body = {
        "subnet": {
            "network_id": id,
            "ip_version": 4,
            "cidr": "172.16.10.0/24",
            "name": "vm_test_subnet",
            "enable_dhcp": True,
            "allocation_pools": [{"start": "172.16.10.10", "end": "172.16.10.254"}],
            "gateway_ip": "172.16.10.1",
            "dns_nameservers": ["8.8.8.8"],
        }
    }
    try:
        res = requests.post(
            f"http://{ip}/v2.0/subnets", json=body, timeout=30, headers=token
        )
        res.raise_for_status()  # 检查是否有错误发生
        print("Request successful!", res.raw)
        if res.ok and res.json().get("subnet").get("id"):
            check_interface_port("vm_test_interface_port",
            id,
            res.json().get("subnet").get("id"),
            device_id,)
    except requests.exceptions.Timeout:
        print("Timeout error occurred. Request timed out after 30 seconds.")
    except requests.exceptions.RequestException as e:
        print("Error occurred:", e)


def create_network(name):
    body = {
        "network": {
            "admin_state_up": True,
            "name": name,
            "provider:network_type": "geneve",
        }
    }
    try:
        res = requests.post(
            f"http://{ip}/v2.0/networks", json=body, timeout=30, headers=token
        )
        res.raise_for_status()  # 检查是否有错误发生
        print("Request successful!", res.status_code)
        if res.json().get("network").get("id"):
            create_subnets(res.json().get("network").get("id"))
    except requests.exceptions.Timeout:
        print("Timeout error occurred. Request timed out after 30 seconds.")
    except requests.exceptions.RequestException as e:
        print("Error occurred:", e)

def delall():
    login()
    res = requests.get(f"http://{ip}/v2.0/networks?name=private_network_mockuser1", headers=token)
    for item in res.json().get("networks"):
        requests.delete(f"http://{ip}/v2.0/networks/{item.get('id')}", headers=token)
    

if __name__ == "__main__":
    # login()
    device_id = check_router("vm_test_router")
    code = check_network("vm_test_network")
    if code == 404:
        create_network()
    # delall()