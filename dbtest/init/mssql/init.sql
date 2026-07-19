IF DB_ID('anaki_dev') IS NULL CREATE DATABASE anaki_dev;
GO
USE anaki_dev;
GO
IF OBJECT_ID('dbo.users') IS NULL
BEGIN
  CREATE TABLE dbo.users (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(255) NOT NULL,
    email NVARCHAR(255) NOT NULL UNIQUE,
    created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
  );
  CREATE TABLE dbo.orders (
    id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT NOT NULL REFERENCES dbo.users(id),
    total DECIMAL(10,2) NOT NULL,
    status NVARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
  );
  INSERT INTO dbo.users (name, email) VALUES
    (N'Fernanda', N'fernanda@example.com'),
    (N'Gabriel', N'gabriel@example.com');
  INSERT INTO dbo.orders (user_id, total, status) VALUES
    (1, 350.00, N'paid'),
    (2, 120.50, N'pending'),
    (1, 42.00, N'shipped');
END
GO
