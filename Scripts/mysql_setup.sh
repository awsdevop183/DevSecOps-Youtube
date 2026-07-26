#!/usr/bin/env bash
# =====================================================================
# setup-mysql-lab.sh - Install MySQL on Ubuntu and build a demo database
#
# Course : DevSecOps Zero to Hero
# Author : Madhukar Reddy | https://youtube.com/@awsandevops
#
# WHAT IT DOES
#   1. Installs MySQL server
#   2. Creates a demo database "shopdb" with realistic tables + data
#   3. Creates a read-only "backupuser" for taking backups
#   4. Writes ~/.my.cnf (chmod 600) so no password ever sits on the CLI
#
#   Safe to re-run - it skips anything that already exists.
#
# USAGE
#   chmod +x setup-mysql-lab.sh
#   ./setup-mysql-lab.sh
# =====================================================================

set -euo pipefail

# --- Settings --------------------------------------------------------
DB_NAME="shopdb"
BACKUP_USER="backupuser"
MYCNF="$HOME/.my.cnf"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[SKIP]${NC} $1"; }

echo -e "${BOLD}${BLUE}=== MySQL lab setup ===${NC}"

# --- 1. Install MySQL ------------------------------------------------
if command -v mysqld &>/dev/null; then
    warn "MySQL already installed"
else
    log "installing MySQL server..."
    sudo apt update -y
    sudo DEBIAN_FRONTEND=noninteractive apt install -y mysql-server
fi

sudo systemctl enable --now mysql
log "MySQL is running: $(mysql --version | awk '{print $3, $4}')"

# --- 2. Generate a password for the backup user ----------------------
# Reuse the existing password if we've already run this script.
if [ -f "$MYCNF" ] && grep -q "^password=" "$MYCNF"; then
    BACKUP_PASS=$(grep "^password=" "$MYCNF" | cut -d= -f2)
    warn "reusing existing backup user password from $MYCNF"
else
    BACKUP_PASS="Bkp@$(openssl rand -hex 8)"
    log "generated a new password for $BACKUP_USER"
fi

# --- 3. Create the database and seed it ------------------------------
# "sudo mysql" works out of the box on Ubuntu via auth_socket - no
# root password needed when you are already root on the box.
log "creating database '$DB_NAME' and demo tables..."

sudo mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME}
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE ${DB_NAME};

CREATE TABLE IF NOT EXISTS customers (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(100) NOT NULL,
  email      VARCHAR(150) NOT NULL UNIQUE,
  city       VARCHAR(80),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS products (
  id     INT AUTO_INCREMENT PRIMARY KEY,
  name   VARCHAR(120) NOT NULL,
  price  DECIMAL(10,2) NOT NULL,
  stock  INT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS orders (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT NOT NULL,
  product_id  INT NOT NULL,
  quantity    INT NOT NULL DEFAULT 1,
  ordered_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (customer_id) REFERENCES customers(id),
  FOREIGN KEY (product_id)  REFERENCES products(id)
);

-- INSERT IGNORE keeps this script safe to re-run
INSERT IGNORE INTO customers (id, name, email, city) VALUES
  (1, 'Ravi Kumar',    'ravi@example.com',    'Hyderabad'),
  (2, 'Anita Sharma',  'anita@example.com',   'Bengaluru'),
  (3, 'John Mathew',   'john@example.com',    'Chennai'),
  (4, 'Priya Nair',    'priya@example.com',   'Kochi'),
  (5, 'Imran Khan',    'imran@example.com',   'Mumbai');

INSERT IGNORE INTO products (id, name, price, stock) VALUES
  (1, 'Mechanical Keyboard', 4999.00, 25),
  (2, 'USB-C Hub',           1899.00, 60),
  (3, '27in Monitor',       18999.00, 12),
  (4, 'Webcam 1080p',        2499.00, 40),
  (5, 'Laptop Stand',        1299.00, 75);

INSERT IGNORE INTO orders (id, customer_id, product_id, quantity) VALUES
  (1, 1, 3, 1), (2, 1, 1, 1), (3, 2, 5, 2),
  (4, 3, 2, 1), (5, 4, 4, 3), (6, 5, 1, 1),
  (7, 2, 3, 1), (8, 5, 5, 2);
SQL

# --- 4. Create the least-privilege backup user -----------------------
# SELECT + LOCK TABLES is all mysqldump needs. No write access, ever.
log "creating read-only user '$BACKUP_USER'..."

sudo mysql -u root <<SQL
CREATE USER IF NOT EXISTS '${BACKUP_USER}'@'localhost'
  IDENTIFIED BY '${BACKUP_PASS}';
ALTER USER '${BACKUP_USER}'@'localhost' IDENTIFIED BY '${BACKUP_PASS}';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER
  ON *.* TO '${BACKUP_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# --- 5. Save credentials safely --------------------------------------
# umask 077 => the file is created 600 (only you can read it).
# This is why the backup script never needs -p on the command line.
log "writing credentials to $MYCNF"
umask 077
cat > "$MYCNF" <<EOF
[client]
user=${BACKUP_USER}
password=${BACKUP_PASS}
EOF
chmod 600 "$MYCNF"

# --- 6. Verify -------------------------------------------------------
echo ""
echo -e "${BOLD}${BLUE}--- Verification ---${NC}"

echo "Tables in ${DB_NAME}:"
mysql -N -e "SHOW TABLES;" "$DB_NAME" | sed 's/^/  /'

echo ""
echo "Row counts:"
for TABLE in customers products orders; do
    COUNT=$(mysql -N -e "SELECT COUNT(*) FROM ${TABLE};" "$DB_NAME")
    echo "  ${TABLE}: ${COUNT}"
done

echo ""
echo "Sample join (top orders):"
mysql -e "
  SELECT c.name AS customer, p.name AS product, o.quantity
  FROM orders o
  JOIN customers c ON c.id = o.customer_id
  JOIN products  p ON p.id = o.product_id
LIMIT 5;" "$DB_NAME"

echo ""
echo -e "${GREEN}${BOLD}Setup complete.${NC}"
echo "  Database    : $DB_NAME"
echo "  Backup user : $BACKUP_USER (read-only)"
echo "  Credentials : $MYCNF $(stat -c '(permissions %a)' "$MYCNF")"
echo ""
echo "Now take a backup with:"
echo "  ./mysql-backup-s3.sh $DB_NAME"