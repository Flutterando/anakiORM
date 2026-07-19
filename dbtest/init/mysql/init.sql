CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  stock INT NOT NULL DEFAULT 0
);

INSERT INTO users (name, email) VALUES
  ('Diego', 'diego@example.com'),
  ('Elisa', 'elisa@example.com');

INSERT INTO products (name, price, stock) VALUES
  ('Keyboard', 199.90, 10),
  ('Mouse', 89.90, 25),
  ('Monitor', 1299.00, 5);
