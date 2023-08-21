#!/bin/bash

cp -r assets bin

for shader in assets/shaders/* ; do
	echo "$shader -> bin/$shader.spv"
	extension="${shader##*.}"
	if [ $extension = "vert" ]; then
		$VULKAN_SDK/bin/glslc -fshader-stage=vert $shader -o bin/$shader.spv
	elif [ $extension = "frag" ]; then
		 $VULKAN_SDK/bin/glslc -fshader-stage=frag $shader -o bin/$shader.spv
	else
		echo "Unsupported file $shader"
	fi
	if [[ $ERRORLEVEL -ne 0 ]]; then
		echo "Error:"ERRORLEVEL && exit
	fi
done
