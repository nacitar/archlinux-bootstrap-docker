FROM archlinux:latest
# if the base image above was ever changed, bootstrap_base_image_name needs updated in the main driver.
COPY bootstrap.sh /
ENTRYPOINT [ "bash", "/bootstrap.sh" ]
