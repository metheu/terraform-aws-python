FROM python:3.7-alpine


COPY ./requirements.txt /app/requirements.txt

RUN pip install -r /app/requirements.txt

WORKDIR /app

COPY ./src/ /app

EXPOSE 5000

ENTRYPOINT ["python"]

CMD ["flask-helloworld.py"]
