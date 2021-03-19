sudo apt-key add "1646B01B86E50310"
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-key add timber.key
echo "deb https://repositories.timber.io/public/vector/deb/ubuntu focal main" | sudo tee /etc/apt/sources.list.d/timber.list