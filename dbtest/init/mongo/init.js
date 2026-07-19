db = db.getSiblingDB('anaki_dev');

db.users.insertMany([
  { name: 'Julia', email: 'julia@example.com', createdAt: new Date() },
  { name: 'Kevin', email: 'kevin@example.com', createdAt: new Date() },
]);

db.articles.insertMany([
  { title: 'Hello Mongo', authorEmail: 'julia@example.com', tags: ['intro', 'mongo'], views: 42, published: true },
  { title: 'Anaki + Mongo', authorEmail: 'kevin@example.com', tags: ['anaki'], views: 7, published: false },
  { title: 'Cockpit DB tour', authorEmail: 'julia@example.com', tags: ['cockpit', 'db'], views: 128, published: true },
]);

db.articles.createIndex({ authorEmail: 1 });
