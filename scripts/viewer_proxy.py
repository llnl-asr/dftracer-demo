#!/usr/bin/env python3
"""Forward a port on the login node to dftracer_server on a compute node.

Usage: viewer_proxy.py LISTEN_HOST LISTEN_PORT TARGET_HOST TARGET_PORT JOB_ID

Login nodes are shared, so if LISTEN_PORT is taken the next free port (up to
+99) is used. The chosen port is printed on the first line of stdout.

A plain TCP relay: requests still carry the server's access token, so the
token check happens on the compute node as before. The proxy exits once the
Slurm job JOB_ID has left the queue.
"""

import asyncio
import subprocess
import sys


async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        writer.close()


async def job_alive(job_id):
    proc = await asyncio.create_subprocess_exec(
        "squeue", "-h", "-j", job_id, "-o", "%T",
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    out, _ = await proc.communicate()
    return bool(out.strip())


async def main(listen_host, listen_port, target_host, target_port, job_id):
    async def handle(client_reader, client_writer):
        try:
            server_reader, server_writer = await asyncio.open_connection(target_host, target_port)
        except OSError:
            client_writer.close()
            return
        await asyncio.gather(pipe(client_reader, server_writer),
                             pipe(server_reader, client_writer))

    for port in range(listen_port, listen_port + 100):
        try:
            server = await asyncio.start_server(handle, listen_host, port)
            break
        except OSError:
            continue
    else:
        sys.exit(f"no free port in {listen_port}-{listen_port + 99}")
    print(port, flush=True)
    async with server:
        while await job_alive(job_id):
            await asyncio.sleep(30)


if __name__ == "__main__":
    host, port, target_host, target_port, job = sys.argv[1:6]
    asyncio.run(main(host, int(port), target_host, int(target_port), job))
