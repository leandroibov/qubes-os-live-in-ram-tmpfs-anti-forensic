# Qubes OS 100% in RAM tmpfs Anti-Forensic Amnesic Script for dom0: Automated

This script automates the configuration to run Qubes dom0 in RAM and utilize appvms and templates in varlibpool, maintaining an anti-forensic and amnesic state similar to Tails OS. It also allows restoration to the original Qubes state.

## How to Install

- For Qubes 4.2, use **4.2.ephemeral.sh** or **4.2.ephemeral_old.sh** (the obsolete version that has been tested for longer).
- For Qubes 4.3, use **4.3.ephemeral.sh**.  
  **Important:** Do not use any other versions to avoid damaging your Qubes OS.

### Installation Example with 4.3.ephemeral.sh

1. Copy the script **4.3.ephemeral.sh** to the appvm **vault** for the user **user** in **/home/user/**.  
   The new path will be **/home/user/4.3.ephemeral.sh**.
2. Open a terminal in dom0 and run:

   ```bash
   qvm-run --pass-io vault 'cat "/home/user/4.3.ephemeral.sh"' > /home/user/4.3.ephemeral.sh
   sudo chmod +x 4.3.ephemeral.sh
   sudo ./4.3.ephemeral.sh

## Option 1: Run Qubes with 100% dom0 in RAM

To use appvms and templates entirely in RAM, you must create appvms and disposable VMs or templates in **varlibpool** within dom0. The Qubes environment becomes hybrid, with dom0 operating 100% in RAM while VMs in the pool on SSD or HDD function normally but are not in RAM.

Upon reboot, a y/n option will appear—use **y** for live mode (like Tails) or **n** to continue with normal SSD dom0.

**Warning:** Creating appvms or templates in the VM pool while dom0 is in RAM may lead to issues, as they cannot be recognized after restart, losing records upon shutdown. The SSD partitions remain but become inaccessible to dom0.

If you configured Qubes for 15 gigabytes of RAM, using option **n** will continue to allocate this amount to dom0, which is inefficient since only 4 gigabytes are needed. Option 2 allows restoration to the original conditions, making dom0 use 4 gigabytes and freeing the rest for other VMs.

## Option 2: Restore Default Qubes Settings

From reboot:

1. Choose option **n**.
   ```bash
   sudo ./4.3.ephemeral.sh
   choose option 2
   reboot
Your Qubes will revert to normal, and the y/n option for live mode will no longer appear at boot.

## Important Notes

dom0 has a default size of 20 gigabytes, initially occupying 6 gigabytes of the system. To add many large templates and appvms totaling, for example, 40 gigabytes, you may need to:

- Increase the size of the dom0 partition.
- Ensure you have enough RAM to accommodate this!

# Doe monero para nos ajudar: (donate XMR)

    87JGuuwXzoMGwQAcSD7cvS7D7iacPpN2f5bVqETbUvCgdEmrPZa12gh5DSiKKRgdU7c5n5x1UvZLj8PQ7AAJSso5CQxgjak
