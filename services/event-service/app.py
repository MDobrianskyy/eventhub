import os
import json
import redis
from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
metrics = PrometheusMetrics(app)

# PostgreSQL connection
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
db = SQLAlchemy(app)

# Redis connection
redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST'),
    port=6379,
    decode_responses=True
)

# --- Model ---

class Event(db.Model):
    id          = db.Column(db.Integer, primary_key=True)
    title       = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    date        = db.Column(db.String(50))
    max_attendees = db.Column(db.Integer, default=100)

    def to_dict(self):
        return {
            'id':             self.id,
            'title':          self.title,
            'description':    self.description,
            'date':           self.date,
            'max_attendees':  self.max_attendees,
        }

# --- Routes ---

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/events', methods=['GET'])
def get_events():
    cached = redis_client.get('events_list')
    if cached:
        return jsonify(json.loads(cached))

    events = Event.query.all()
    result = [e.to_dict() for e in events]

    redis_client.setex('events_list', 60, json.dumps(result))
    return jsonify(result)

@app.route('/events/<int:event_id>', methods=['GET'])
def get_event(event_id):
    cache_key = f'event_{event_id}'
    cached = redis_client.get(cache_key)
    if cached:
        return jsonify(json.loads(cached))

    event = Event.query.get_or_404(event_id)
    result = event.to_dict()

    redis_client.setex(cache_key, 120, json.dumps(result))
    return jsonify(result)

@app.route('/events', methods=['POST'])
def create_event():
    data = request.get_json()
    event = Event(
        title=data['title'],
        description=data.get('description', ''),
        date=data.get('date', ''),
        max_attendees=data.get('max_attendees', 100)
    )
    db.session.add(event)
    db.session.commit()

    # інвалідуємо кеш списку — він тепер застарілий
    redis_client.delete('events_list')

    return jsonify(event.to_dict()), 201

@app.route('/events/<int:event_id>', methods=['DELETE'])
def delete_event(event_id):
    event = Event.query.get_or_404(event_id)
    db.session.delete(event)
    db.session.commit()

    redis_client.delete('events_list')
    redis_client.delete(f'event_{event_id}')

    return '', 204

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(host='0.0.0.0', port=5001)
