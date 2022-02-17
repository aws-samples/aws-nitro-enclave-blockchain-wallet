FROM python:3.8

WORKDIR /usr/src/app

COPY ./app.py ./

COPY requirements.txt ./
RUN pip3 install -r /usr/src/app/requirements.txt

CMD [ "python", "./app.py" ]