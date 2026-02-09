from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()

class Employee(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    # Allows easy access to related schedules
    schedules = db.relationship('Schedule', backref='employee', lazy=True, cascade="all, delete-orphan")

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name
        }

class Schedule(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    employee_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=False)
    date = db.Column(db.Date, nullable=False)
    shift_type = db.Column(db.String(20), nullable=False, default='Off') 
    # shift_type values: 'Day', 'Night', 'Off', 'Holiday'

    def to_dict(self):
        return {
            'id': self.id,
            'employee_id': self.employee_id,
            'date': self.date.isoformat(),
            'shift_type': self.shift_type
        }

class DailyInfo(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    date = db.Column(db.Date, unique=True, nullable=False)
    stock = db.Column(db.String(50), default='')
    event = db.Column(db.String(255), default='')

    def to_dict(self):
        return {
            'date': self.date.isoformat(),
            'stock': self.stock,
            'event': self.event
        }
