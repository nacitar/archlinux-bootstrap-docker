FROM archlinux:latest
# if the base image above was ever changed, pacstrap_base_image_name needs updated in the main driver.

COPY pacstrap.sh /
ENTRYPOINT [ "bash", "/pacstrap.sh" ]
