import os
from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
app.url_map.strict_slashes = False
metrics = PrometheusMetrics(app)

# PostgreSQL connection
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
db = SQLAlchemy(app)

# --- Model ---

class Registration(db.Model):
    id       = db.Column(db.Integer, primary_key=True)
    event_id = db.Column(db.Integer, nullable=False)
    name     = db.Column(db.String(200), nullable=False)
    email    = db.Column(db.String(200), nullable=False)

    def to_dict(self):
        return {
            'id':       self.id,
            'event_id': self.event_id,
            'name':     self.name,
            'email':    self.email,
        }

# --- Routes ---

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/registrations', methods=['POST'])
def create_registration():
    data = request.get_json()
    registration = Registration(
        event_id=data['event_id'],
        name=data['name'],
        email=data['email']
    )
    db.session.add(registration)
    db.session.commit()
    return jsonify(registration.to_dict()), 201

@app.route('/registrations/event/<int:event_id>', methods=['GET'])
def get_registrations(event_id):
    registrations = Registration.query.filter_by(event_id=event_id).all()
    return jsonify([r.to_dict() for r in registrations])

@app.route('/registrations/count/<int:event_id>', methods=['GET'])
def get_count(event_id):
    count = Registration.query.filter_by(event_id=event_id).count()
    return jsonify({'event_id': event_id, 'count': count})

with app.app_context():
    try:
        db.create_all()
    except Exception:
        pass


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002)
